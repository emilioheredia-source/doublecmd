{
   Double commander
   -------------------------------------------------------------------------
   Wfx plugin for working with File Transfer Protocol

   Copyright (C) 2013-2025 Alexander Koblov (alexx2000@mail.ru)

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
}

unit SftpSend;

{$mode delphi}
{$pointermath on}

interface

uses
  Classes, SysUtils, WfxPlugin, ftpsend, ScpSend, libssh, FtpAdv;

type
  // What a remote path is, without following a symlink (lstat)
  TRemoteKind = (rkNone, rkFile, rkLink, rkDir, rkOther, rkError);

  { TSftpSend }

  TSftpSend = class(TScpSend)
  private
    function FileClose(Handle: Pointer): Boolean;
    // Block until the socket is ready in the direction libssh2 is waiting on.
    procedure WaitSocket;
{$IFDEF UNIX}
    // Reproduce a remote symbolic link locally instead of downloading the
    // content its target holds. False when the link cannot be read or created.
    function RetrieveLink(const FileName: String): Boolean;
{$ENDIF}
  private
    // Directory prefetch while a sync compare lists a whole tree, see
    // BeginSyncSearch. Listings are keyed by path (with trailing '/').
    FPrefetch: Boolean;
    FPrefetchCache: TStringList;
    FPrefetchChannels: array of PLIBSSH2_SFTP;
    FPrefetchPending: TStringList;  // found, not fetched yet; top = next
    FPrefetchSeen: TStringList;     // queued or listed during this compare
    procedure Prefetch(const First: String);
    procedure FreePrefetchCache;
    procedure FillFindData(const AName: String; const Attributes: LIBSSH2_SFTP_ATTRIBUTES;
      LinkTarget: PLIBSSH2_SFTP_ATTRIBUTES; var FindData: TWin32FindDataW);
    // Remote path inspection and changes that never follow a symlink. They
    // judge by the result on the server, not by return codes: libssh2
    // reports an error for most symlink requests that did succeed.
    function RemoteKind(const Path: String): TRemoteKind;
    function RemoteLinkIs(const Path, Target: String): Boolean;
    function RemoteRemoveLink(const Path: String): Boolean;
    function StoreLink(const FileName, LinkTarget: String): Boolean;
  protected
    FCopySCP: Boolean;
    FSFTPSession: PLIBSSH2_SFTP;
  protected
    function Connect: Boolean; override;
    function LinkAlive: Boolean; override;
  public
    constructor Create(const Encoding: String); override;
    destructor Destroy; override;
    function Login: Boolean; override;
    function Logout: Boolean; override;
    procedure BeginSyncSearch; override;
    procedure EndSyncSearch; override;
    function GetCurrentDir: String; override;
    function FileSize(const FileName: String): Int64; override;
    function CreateDir(const Directory: string): Boolean; override;
    function DeleteDir(const Directory: string): Boolean; override;
    function DeleteFile(const FileName: string): Boolean; override;
    function ChangeWorkingDir(const Directory: string): Boolean; override;
    function RenameFile(const OldName, NewName: string): Boolean; override;
    function ChangeMode(const FileName, Mode: String): Boolean; override;
    function StoreFile(const FileName: string; Restore: Boolean): Boolean; override;
    function RetrieveFile(const FileName: string; FileSize: Int64; Restore: Boolean): Boolean; override;
  public
    function FsFindFirstW(const Path: String; var FindData: TWin32FindDataW): Pointer; override;
    function FsFindNextW(Handle: Pointer; var FindData: TWin32FindDataW): BOOL; override;
    function FsFindClose(Handle: Pointer): Integer; override;
    function FsSetTime(const FileName: String; LastAccessTime, LastWriteTime: PFileTime): BOOL; override;
  public
    property CopySCP: Boolean read FCopySCP write FCopySCP;
  end;

implementation

uses
  LazUTF8, DCBasicTypes, DCDateTimeUtils, DCStrUtils, DCOSUtils, CTypes,
  DCClassesUtf8, DCFileAttributes, DCConvertEncoding{$IFDEF UNIX}, BaseUnix{$ENDIF};

const
  READ_BUFFER_SIZE  = 131072;
  WRITE_BUFFER_SIZE = MAX_SFTP_OUTGOING_SIZE * 20;

  // Directory prefetch: SFTP channels used at once (the main one included;
  // OpenSSH allows 10 per connection by default), directories fetched per
  // batch - bounded so a cancelled compare does not wait long - and the
  // number of fetched directories below which the cache is topped up.
  PREFETCH_CHANNELS = 8;
  PREFETCH_BATCH = 64;
  PREFETCH_LOW = 16;

type
  TDirEntry = record
    Name: String;                        // as the server sent it
    Attributes: LIBSSH2_SFTP_ATTRIBUTES;
    HasTarget: Boolean;                  // a symlink whose target could be stat'ed
    Target: LIBSSH2_SFTP_ATTRIBUTES;
  end;

  { TDirListing }

  // A directory read completely ahead of time
  TDirListing = class
    Path: String;
    Failed: Boolean;
    Closed: Boolean;           // directory handle closed, entries complete
    PendingLinks: Integer;     // symlinks whose target is still being stat'ed
    Count: Integer;
    Entries: array of TDirEntry;
    procedure Add(const AName: String; const Attrs: LIBSSH2_SFTP_ATTRIBUTES);
  end;

  PFindRec = ^TFindRec;
  TFindRec = record
    Path: String;
    Handle: PLIBSSH2_SFTP_HANDLE;
    // When set, entries are served from this prefetched listing, not Handle
    Listing: TDirListing;
    Index: Integer;
  end;

  TPrefetchStage = (psIdle, psOpen, psRead, psClose, psStat);

  // One SFTP channel, non-blocking, reading one directory (psOpen..psClose)
  // or stat'ing one symlink target in Listing (psStat)
  TPrefetchWorker = record
    Sftp: PLIBSSH2_SFTP;
    Stage: TPrefetchStage;
    Handle: PLIBSSH2_SFTP_HANDLE;
    Listing: TDirListing;
    LinkIndex: Integer;
  end;

function IsLink(const Attributes: LIBSSH2_SFTP_ATTRIBUTES): Boolean; inline;
begin
  Result:= (Attributes.permissions and S_IFMT) = S_IFLNK;
end;

{ TDirListing }

procedure TDirListing.Add(const AName: String; const Attrs: LIBSSH2_SFTP_ATTRIBUTES);
begin
  if Count = Length(Entries) then
    SetLength(Entries, Count * 2 + 16);
  Entries[Count].Name:= AName;
  Entries[Count].Attributes:= Attrs;
  Entries[Count].HasTarget:= False;
  Inc(Count);
end;

{ TSftpSend }

procedure TSftpSend.WaitSocket;
begin
  // On EAGAIN, wait on the direction libssh2 actually needs. During an upload a
  // full send buffer blocks OUTBOUND: waiting on CanRead (as the read path does)
  // would then stall the whole CanRead timeout every packet - throttling upload
  // throughput to a crawl. Ask libssh2 which way it is blocked and wait on that.
  if (libssh2_session_block_directions(FSession) and LIBSSH2_SESSION_BLOCK_OUTBOUND) <> 0 then
    FSock.CanWrite(10)
  else
    FSock.CanRead(10);
end;

function TSftpSend.FileClose(Handle: Pointer): Boolean;
begin
  FLastError:= 0;
  if Assigned(Handle) then
  repeat
    FLastError:= libssh2_sftp_close(Handle);
    // Only wait on the socket when the close has not finished yet
    // (EAGAIN). Waiting after a successful close blocks for the full
    // CanRead timeout with nothing to read, adding a fixed ~10 ms stall
    // to every single file - crippling for many-small-files transfers.
    if (FLastError = LIBSSH2_ERROR_EAGAIN) then
    begin
      DoProgress(100);
      FSock.CanRead(10);
    end;
  until FLastError <> LIBSSH2_ERROR_EAGAIN;
  Result:= (FLastError = 0);
end;

function TSftpSend.Connect: Boolean;
begin
  Result:= inherited Connect;

  if Result then
  begin
    FSFTPSession := libssh2_sftp_init(FSession);

    Result:= Assigned(FSFTPSession);

    if not Result then begin
      libssh2_session_free(FSession);
      FSock.CloseSocket;
    end;
  end;
end;

constructor TSftpSend.Create(const Encoding: String);
begin
  inherited Create(Encoding);
  FCanResume := True;
end;

destructor TSftpSend.Destroy;
begin
  // The channels go with the session; only the cached listings are ours
  FreePrefetchCache;
  FreeAndNil(FPrefetchCache);
  FreeAndNil(FPrefetchPending);
  FreeAndNil(FPrefetchSeen);
  inherited Destroy;
end;

procedure TSftpSend.BeginSyncSearch;
begin
  if FCopySCP then Exit;
  if FPrefetchCache = nil then
  begin
    FPrefetchCache:= TStringList.Create;
    FPrefetchCache.Sorted:= True;
    FPrefetchCache.CaseSensitive:= True;
    FPrefetchPending:= TStringList.Create;
    FPrefetchSeen:= TStringList.Create;
    FPrefetchSeen.Sorted:= True;
    FPrefetchSeen.CaseSensitive:= True;
  end;
  FreePrefetchCache;
  FPrefetch:= True;
end;

procedure TSftpSend.EndSyncSearch;
var
  I: Integer;
begin
  FPrefetch:= False;
  FreePrefetchCache;
  for I:= 0 to High(FPrefetchChannels) do
    libssh2_sftp_shutdown(FPrefetchChannels[I]);
  FPrefetchChannels:= nil;
end;

procedure TSftpSend.FreePrefetchCache;
var
  I: Integer;
begin
  if FPrefetchCache = nil then Exit;
  for I:= 0 to FPrefetchCache.Count - 1 do
    FPrefetchCache.Objects[I].Free;
  FPrefetchCache.Clear;
  FPrefetchPending.Clear;
  FPrefetchSeen.Clear;
end;

procedure TSftpSend.Prefetch(const First: String);
var
  I, Rc, Busy, Active, Listed: Integer;
  FirstPath: String;
  Progress: Boolean;
  Sftp: PLIBSSH2_SFTP;
  Workers: array of TPrefetchWorker;
  // Symlinks waiting for their target to be stat'ed, by any free channel:
  // pairs of (listing, entry index)
  LinkJobs: TFPList;
  LinkIndexes: array of Integer;
  InFlight: TFPList;
  Attrs: LIBSSH2_SFTP_ATTRIBUTES;
  EntryName: String;
  AName: array[0..1023] of AnsiChar;
  AFullData: array[0..2047] of AnsiChar;

  // The directory is complete: cache it and queue its subdirectories. They go
  // on top of the pending stack in the order the compare visits them (names
  // ascending), so what is fetched next is what the compare asks for next.
  procedure Finish(Listing: TDirListing);
  var
    J: Integer;
    SubDirs: TStringList;
  begin
    if not Listing.Failed then
    begin
      SubDirs:= TStringList.Create;
      try
        for J:= 0 to Listing.Count - 1 do
          with Listing.Entries[J] do
            // Real directories only: following links could loop
            if ((Attributes.permissions and S_IFMT) = S_IFDIR) and
               (Name <> '.') and (Name <> '..') then
              SubDirs.Add(Name);
        SubDirs.Sort;
        for J:= SubDirs.Count - 1 downto 0 do
          if FPrefetchSeen.IndexOf(Listing.Path + SubDirs[J] + '/') < 0 then
          begin
            FPrefetchSeen.Add(Listing.Path + SubDirs[J] + '/');
            FPrefetchPending.Add(Listing.Path + SubDirs[J] + '/');
          end;
      finally
        SubDirs.Free;
      end;
    end;
    InFlight.Remove(Listing);
    FPrefetchCache.AddObject(Listing.Path, Listing);
  end;

  // Entries read: queue the symlinks for their stat, share the work out
  procedure QueueLinks(Listing: TDirListing);
  var
    J: Integer;
  begin
    if Listing.Failed then Exit;
    for J:= 0 to Listing.Count - 1 do
      if IsLink(Listing.Entries[J].Attributes) then
      begin
        LinkJobs.Add(Listing);
        SetLength(LinkIndexes, LinkJobs.Count);
        LinkIndexes[LinkJobs.Count - 1]:= J;
        Inc(Listing.PendingLinks);
      end;
  end;

  procedure LinkDone(Listing: TDirListing);
  begin
    Dec(Listing.PendingLinks);
    if Listing.Closed and (Listing.PendingLinks = 0) then Finish(Listing);
  end;

  // Advance one worker by one call. False when that call would block.
  function Step(var W: TPrefetchWorker): Boolean;
  begin
    Result:= True;
    case W.Stage of
      psOpen:
        begin
          W.Handle:= libssh2_sftp_opendir(W.Sftp, PAnsiChar(W.Listing.Path));
          if (W.Handle = nil) then
          begin
            if libssh2_session_last_errno(FSession) = LIBSSH2_ERROR_EAGAIN then
              Exit(False);
            W.Listing.Failed:= True;
            W.Listing.Closed:= True;
            Finish(W.Listing);
            W.Stage:= psIdle;
          end
          else W.Stage:= psRead;
        end;
      psRead:
        begin
          Rc:= libssh2_sftp_readdir_ex(W.Handle, AName, SizeOf(AName),
                                       AFullData, SizeOf(AFullData), @Attrs);
          if Rc = LIBSSH2_ERROR_EAGAIN then Exit(False);
          if Rc > 0 then
          begin
            SetString(EntryName, PAnsiChar(@AName[0]), Rc);
            W.Listing.Add(EntryName, Attrs);
          end
          else begin
            // 0 is the end of the directory, anything else an error
            if Rc < 0 then W.Listing.Failed:= True;
            QueueLinks(W.Listing);
            W.Stage:= psClose;
          end;
        end;
      psClose:
        begin
          if libssh2_sftp_closedir(W.Handle) = LIBSSH2_ERROR_EAGAIN then
            Exit(False);
          W.Listing.Closed:= True;
          if W.Listing.PendingLinks = 0 then Finish(W.Listing);
          W.Stage:= psIdle;
        end;
      psStat:
        with W.Listing.Entries[W.LinkIndex] do
        begin
          // Tells a link to a directory from any other link
          Rc:= libssh2_sftp_stat(W.Sftp, PAnsiChar(W.Listing.Path + Name), @Target);
          if Rc = LIBSSH2_ERROR_EAGAIN then Exit(False);
          HasTarget:= (Rc = 0);
          LinkDone(W.Listing);
          W.Stage:= psIdle;
        end;
    end;
  end;

  // Give an idle worker something to do: symlinks first, so directories that
  // have been read complete soonest; then First; then the top of the pending
  // stack. Past the batch size, idle channels still take directories while
  // another channel is busy, up to a hard cap that keeps a cancelled compare
  // responsive.
  function Assign(var W: TPrefetchWorker): Boolean;
  var
    APath: String;
  begin
    Result:= True;
    if LinkJobs.Count > 0 then
    begin
      W.Listing:= TDirListing(LinkJobs[LinkJobs.Count - 1]);
      W.LinkIndex:= LinkIndexes[LinkJobs.Count - 1];
      LinkJobs.Delete(LinkJobs.Count - 1);
      W.Stage:= psStat;
      Exit;
    end;
    if not ((Listed < PREFETCH_BATCH) or
            ((Active > 0) and (Listed < 4 * PREFETCH_BATCH))) then
      Exit(False);
    if FirstPath <> '' then
    begin
      APath:= FirstPath;
      FirstPath:= '';
    end
    else if FPrefetchPending.Count > 0 then
    begin
      APath:= FPrefetchPending[FPrefetchPending.Count - 1];
      FPrefetchPending.Delete(FPrefetchPending.Count - 1);
    end
    else
      Exit(False);
    Inc(Listed);
    W.Listing:= TDirListing.Create;
    W.Listing.Path:= APath;
    InFlight.Add(W.Listing);
    W.Stage:= psOpen;
  end;

begin
  // Extra channels on the same SSH connection, opened once per compare. The
  // server may allow fewer; work with whatever it grants.
  if FPrefetchChannels = nil then
    for I:= 2 to PREFETCH_CHANNELS do
    begin
      Sftp:= libssh2_sftp_init(FSession);
      if Sftp = nil then Break;
      SetLength(FPrefetchChannels, Length(FPrefetchChannels) + 1);
      FPrefetchChannels[High(FPrefetchChannels)]:= Sftp;
    end;

  SetLength(Workers, Length(FPrefetchChannels) + 1);
  for I:= 0 to High(Workers) do
  begin
    if I = 0 then
      Workers[I].Sftp:= FSFTPSession
    else
      Workers[I].Sftp:= FPrefetchChannels[I - 1];
    Workers[I].Stage:= psIdle;
  end;

  Listed:= 0;
  FirstPath:= First;
  LinkJobs:= TFPList.Create;
  InFlight:= TFPList.Create;
  libssh2_session_set_blocking(FSession, 0);
  try
    // Every channel works on a directory (or symlink) of its own, so the
    // round trips of up to PREFETCH_CHANNELS requests overlap.
    repeat
      Busy:= 0;
      Progress:= False;
      Active:= 0;
      for I:= 0 to High(Workers) do
        if Workers[I].Stage <> psIdle then Inc(Active);
      for I:= 0 to High(Workers) do
      begin
        if (Workers[I].Stage = psIdle) and not Assign(Workers[I]) then Continue;
        Inc(Busy);
        if Step(Workers[I]) then Progress:= True;
      end;
      if (Busy > 0) and not Progress then WaitSocket;
    until Busy = 0;
  finally
    libssh2_session_set_blocking(FSession, 1);
    // Only after an exception is anything left half done
    for I:= 0 to InFlight.Count - 1 do
      TDirListing(InFlight[I]).Free;
    InFlight.Free;
    LinkJobs.Free;
  end;
end;

function TSftpSend.Login: Boolean;
var
  Return: Integer;
begin
  Result:= Connect;
  if Result then
  begin
    if FAuto then DetectEncoding;

    if (Length(FCurrentDir) = 0) then
    begin
      SetLength(FCurrentDir, MAX_PATH + 1);
      Return:= libssh2_sftp_realpath(FSFTPSession, '.', PAnsiChar(FCurrentDir), MAX_PATH);
      if Return < 1 then
        FCurrentDir:= '/'
      else begin
        SetLength(FCurrentDir, Return);
        FCurrentDir:= CeUtf16ToUtf8(ServerToClient(FCurrentDir));
      end;
      DoStatus(False, 'Remote directory: ' + FCurrentDir);
    end;
  end;
end;

function TSftpSend.Logout: Boolean;
begin
  Result:= libssh2_sftp_shutdown(FSFTPSession) = 0;
  Result:= Result and inherited Logout;
end;

function TSftpSend.GetCurrentDir: String;
begin
  Result:= FCurrentDir;
end;

function TSftpSend.FileSize(const FileName: String): Int64;
var
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  repeat
    FLastError:= libssh2_sftp_stat(FSFTPSession, PAnsiChar(FileName), @Attributes);
    if (FLastError = 0) then Exit(Attributes.filesize);
    // Only wait on the socket when the stat has not finished yet (EAGAIN).
    // Waiting after a definitive answer -- and "no such file" is the common
    // answer when uploading -- blocks for the full CanRead timeout with
    // nothing to read, adding a fixed ~10 ms stall to every file. Same guard
    // FileClose already uses.
    if (FLastError = LIBSSH2_ERROR_EAGAIN) then
    begin
      FSock.CanRead(10);
      DoProgress(0);
    end;
  until FLastError <> LIBSSH2_ERROR_EAGAIN;
  Result:= -1;
end;

function TSftpSend.CreateDir(const Directory: string): Boolean;
var
  Return: Integer;
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  Return:= libssh2_sftp_mkdir(FSFTPSession,
                              PAnsiChar(Directory),
                              LIBSSH2_SFTP_S_IRWXU or
                              LIBSSH2_SFTP_S_IRGRP or LIBSSH2_SFTP_S_IXGRP or
                              LIBSSH2_SFTP_S_IROTH or LIBSSH2_SFTP_S_IXOTH);
  if (Return = 0) then
    // We just created this directory, so it is known-empty: files copied into
    // it during this operation cannot pre-exist, letting FsPutFile skip the
    // per-file existence stat (see MarkDirFresh / IsDirFresh).
    MarkDirFresh(Directory)
  else begin
    Return:= libssh2_sftp_stat(FSFTPSession, PAnsiChar(Directory), @Attributes);
  end;
  Result:= (Return = 0);
end;

function TSftpSend.DeleteDir(const Directory: string): Boolean;
begin
  Result:= libssh2_sftp_rmdir(FSFTPSession, PAnsiChar(Directory)) = 0;
end;

function TSftpSend.DeleteFile(const FileName: string): Boolean;
begin
  Result:= libssh2_sftp_unlink(FSFTPSession, PAnsiChar(FileName)) = 0;
end;

function TSftpSend.ChangeWorkingDir(const Directory: string): Boolean;
var
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  Result:= libssh2_sftp_stat(FSFTPSession, PAnsiChar(Directory), @Attributes) = 0;
  if Result then FCurrentDir:= Directory;
end;

function TSftpSend.RenameFile(const OldName, NewName: string): Boolean;
begin
  Result:= libssh2_sftp_rename(FSFTPSession, PAnsiChar(OldName), PAnsiChar(NewName)) = 0;
end;

function TSftpSend.LinkAlive: Boolean;
var
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  // One round-trip lets libssh2 consume whatever is pending (a keep-alive is
  // answered, a disconnect message is noticed). Any SFTP status reply, even
  // an error, proves the link works.
  FLastError:= libssh2_sftp_stat(FSFTPSession, '.', @Attributes);
  Result:= (FLastError = 0) or (FLastError = LIBSSH2_ERROR_SFTP_PROTOCOL);
end;

function TSftpSend.ChangeMode(const FileName, Mode: String): Boolean;
var
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  Attributes.permissions:= OctToDec(Mode);
  Attributes.flags:= LIBSSH2_SFTP_ATTR_PERMISSIONS;
  Result:= libssh2_sftp_setstat(FSFTPSession, PAnsiChar(FileName), @Attributes) = 0;
end;

function TSftpSend.RemoteKind(const Path: String): TRemoteKind;
var
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  repeat
    FLastError:= libssh2_sftp_lstat(FSFTPSession, PAnsiChar(Path), @Attributes);
    if FLastError = LIBSSH2_ERROR_EAGAIN then WaitSocket;
  until FLastError <> LIBSSH2_ERROR_EAGAIN;
  if FLastError <> 0 then
  begin
    if (FLastError = LIBSSH2_ERROR_SFTP_PROTOCOL) and
       (libssh2_sftp_last_error(FSFTPSession) = LIBSSH2_FX_NO_SUCH_FILE) then
      Exit(rkNone);
    Exit(rkError);
  end;
  case Attributes.permissions and S_IFMT of
    S_IFREG: Result:= rkFile;
    S_IFLNK: Result:= rkLink;
    S_IFDIR: Result:= rkDir;
    else     Result:= rkOther;
  end;
end;

function TSftpSend.RemoteLinkIs(const Path, Target: String): Boolean;
var
  ALength: cint;
  ATarget: array[0..4095] of AnsiChar;
begin
  repeat
    ALength:= libssh2_sftp_readlink(FSFTPSession, PAnsiChar(Path), ATarget, SizeOf(ATarget));
    if ALength = LIBSSH2_ERROR_EAGAIN then WaitSocket;
  until ALength <> LIBSSH2_ERROR_EAGAIN;
  Result:= (ALength = Length(Target)) and (ALength > 0) and
           CompareMem(@ATarget[0], PAnsiChar(Target), ALength);
end;

function TSftpSend.RemoteRemoveLink(const Path: String): Boolean;
begin
  // Only a symlink is ever removed here; the link goes, never what it points at
  if RemoteKind(Path) <> rkLink then Exit(False);
  repeat
    FLastError:= libssh2_sftp_unlink(FSFTPSession, PAnsiChar(Path));
    if FLastError = LIBSSH2_ERROR_EAGAIN then WaitSocket;
  until FLastError <> LIBSSH2_ERROR_EAGAIN;
  Result:= RemoteKind(Path) = rkNone;
end;

function TSftpSend.StoreLink(const FileName, LinkTarget: String): Boolean;
var
  I, Rc: Integer;
  TempName: String;
  Existing: TRemoteKind;

  procedure MakeLink(const APath: String);
  begin
    // The return code is not trusted (see RemoteKind); callers check the result
    repeat
      Rc:= libssh2_sftp_symlink(FSFTPSession, PAnsiChar(LinkTarget), PAnsiChar(APath));
      if Rc = LIBSSH2_ERROR_EAGAIN then WaitSocket;
    until Rc <> LIBSSH2_ERROR_EAGAIN;
  end;

begin
  Result:= False;
  Existing:= RemoteKind(FileName);
  case Existing of
    rkNone:
      begin
        MakeLink(FileName);
        Exit(RemoteLinkIs(FileName, LinkTarget));
      end;
    rkLink:
      if RemoteLinkIs(FileName, LinkTarget) then Exit(True);
    rkFile: ;
    // Never replace a directory (or anything unknown) with a link
    else Exit;
  end;

  // Something is there to be replaced. Build the new link beside it first and
  // check it, so a failure leaves the destination exactly as it was.
  TempName:= EmptyStr;
  for I:= 1 to 3 do
  begin
    TempName:= Copy(FileName, 1, LastDelimiter('/', FileName)) + '.' +
               Copy(FileName, LastDelimiter('/', FileName) + 1, MaxInt) +
               '.dclink-' + IntToHex(Random($7FFFFFFF), 8);
    if RemoteKind(TempName) = rkNone then Break;
    TempName:= EmptyStr;
  end;
  if TempName = EmptyStr then Exit;
  MakeLink(TempName);
  if not RemoteLinkIs(TempName, LinkTarget) then
  begin
    RemoteRemoveLink(TempName);
    Exit;
  end;

  if Assigned(libssh2_sftp_posix_rename_ex) then
  begin
    // Replaces the destination in one step
    repeat
      Rc:= libssh2_sftp_posix_rename_ex(FSFTPSession, PAnsiChar(TempName), Length(TempName),
                                        PAnsiChar(FileName), Length(FileName));
      if Rc = LIBSSH2_ERROR_EAGAIN then WaitSocket;
    until Rc <> LIBSSH2_ERROR_EAGAIN;
  end;
  if RemoteKind(TempName) <> rkNone then
  begin
    // No posix-rename on this server or library: remove the old entry, then
    // rename. Removing is only ever done for a symlink or a regular file.
    if Existing = rkLink then
      RemoteRemoveLink(FileName)
    else if RemoteKind(FileName) = rkFile then
    repeat
      FLastError:= libssh2_sftp_unlink(FSFTPSession, PAnsiChar(FileName));
      if FLastError = LIBSSH2_ERROR_EAGAIN then WaitSocket;
    until FLastError <> LIBSSH2_ERROR_EAGAIN;
    if RemoteKind(FileName) = rkNone then
    repeat
      Rc:= libssh2_sftp_rename(FSFTPSession, PAnsiChar(TempName), PAnsiChar(FileName));
      if Rc = LIBSSH2_ERROR_EAGAIN then WaitSocket;
    until Rc <> LIBSSH2_ERROR_EAGAIN;
  end;
  Result:= RemoteLinkIs(FileName, LinkTarget) and (RemoteKind(TempName) = rkNone);
  // A failed swap leaves the destination untouched; drop the spare link
  if not Result then RemoteRemoveLink(TempName);
end;

function TSftpSend.StoreFile(const FileName: string; Restore: Boolean): Boolean;
var
  Index: PtrInt;
  FBuffer: PByte;
  FileSize: Int64;
  BytesRead: Integer;
  BytesToRead: Integer;
  BytesWritten: PtrInt;
  BytesToWrite: Integer;
  SendStream: TFileStreamEx;
  TotalBytesToWrite: Int64 = 0;
  TargetHandle: PLIBSSH2_SFTP_HANDLE = nil;
  Flags: cint = LIBSSH2_FXF_CREAT or LIBSSH2_FXF_WRITE;
  OpenMode: clong = $1A0;
  MadeWritable: Boolean = False;
  Replaced: Integer = 0;
{$IFDEF UNIX}
  LocalStat: BaseUnix.TStat;
  UploadAttrs: LIBSSH2_SFTP_ATTRIBUTES;
  LinkTarget: String;
{$ENDIF}

  function SetRemoteMode(Mode: clong): Boolean;
  var
    Attributes: LIBSSH2_SFTP_ATTRIBUTES;
  begin
    FillChar(Attributes, SizeOf(Attributes), 0);
    Attributes.permissions:= Mode;
    Attributes.flags:= LIBSSH2_SFTP_ATTR_PERMISSIONS;
    repeat
      FLastError:= libssh2_sftp_setstat(FSFTPSession, PAnsiChar(FileName), @Attributes);
      if FLastError = LIBSSH2_ERROR_EAGAIN then FSock.CanRead(10);
    until FLastError <> LIBSSH2_ERROR_EAGAIN;
    Result:= (FLastError = 0);
  end;

begin
  if FCopySCP then begin
    Result:= inherited StoreFile(FileName, Restore);
    Exit;
  end;

{$IFDEF UNIX}
  // A local symlink is recreated as a symlink, and nothing else: there is no
  // falling back to uploading what it points at. That fallback used to open
  // the destination for writing after the link had in fact been created
  // (libssh2 reports failure for a symlink that succeeded), so the server
  // followed the new link and overwrote the file it points to.
  if (fpLStat(FDirectFileName, LocalStat) = 0) and FPS_ISLNK(LocalStat.st_mode) then
  begin
    LinkTarget:= fpReadLink(FDirectFileName);
    Exit((Length(LinkTarget) > 0) and StoreLink(FileName, LinkTarget));
  end;
{$ENDIF}

  SendStream := TFileStreamEx.Create(FDirectFileName, fmOpenRead or fmShareDenyWrite);

  TargetName:= PWideChar(ServerToClient(FileName));
  SourceName:= PWideChar(CeUtf8ToUtf16(FDirectFileName));

  FileSize:= SendStream.Size;
  FBuffer:= GetMem(WRITE_BUFFER_SIZE);
  libssh2_session_set_blocking(FSession, 0);
  try
    if not Restore then
    begin
      TotalBytesToWrite:= FileSize;
      // Create only: this fails on anything already there, a dangling
      // symlink included, so nothing is ever written through a link. What is
      // in the way is looked at only then, keeping a new file at one request.
      Flags:= Flags or LIBSSH2_FXF_EXCL;
      // An overwrite most likely finds something: look first, saving the
      // failed create. Same rules as below.
      if FExpectExisting then
      begin
        Inc(Replaced);
        case RemoteKind(FileName) of
          rkNone: ;
          rkFile: Flags:= (Flags and not LIBSSH2_FXF_EXCL) or LIBSSH2_FXF_TRUNC;
          rkLink: if not RemoteRemoveLink(FileName) then Exit(False);
          else Exit(False);
        end;
      end;
    end
    else begin
      // Resuming appends to what is there: only ever to a regular file
      if RemoteKind(FileName) <> rkFile then Exit(False);
      TotalBytesToWrite:= Self.FileSize(FileName);
      if (FileSize = TotalBytesToWrite) then Exit(True);
      if TotalBytesToWrite < 0 then TotalBytesToWrite:= 0;
      SendStream.Seek(TotalBytesToWrite, soBeginning);
      TotalBytesToWrite := FileSize - TotalBytesToWrite;
      Flags:= Flags or LIBSSH2_FXF_APPEND;
    end;

{$IFDEF UNIX}
    // Create the remote file directly with the local file's permission bits,
    // so we don't need a separate setstat round-trip afterwards. Like any
    // normal file creation this is subject to the server's umask.
    if fpStat(FDirectFileName, LocalStat) = 0 then
      OpenMode:= LocalStat.st_mode and $0FFF;
{$ENDIF}

    // Open remote file
    repeat
      TargetHandle:= libssh2_sftp_open(FSFTPSession,
                                       PAnsiChar(FileName),
                                       Flags, OpenMode);
      if (TargetHandle = nil) then
      begin
        FLastError:= libssh2_session_last_errno(FSession);
        if (FLastError <> LIBSSH2_ERROR_EAGAIN) and
           ((Flags and LIBSSH2_FXF_EXCL) <> 0) and (Replaced < 3) then
        begin
          // Something is in the way: replace a symlink (the link, never its
          // target), overwrite a regular file, and refuse anything else.
          Inc(Replaced);
          case RemoteKind(FileName) of
            rkLink:
              if not RemoteRemoveLink(FileName) then Exit(False);
            rkFile:
              Flags:= (Flags and not LIBSSH2_FXF_EXCL) or LIBSSH2_FXF_TRUNC;
            else
              // rkNone: creating failed for another reason (permissions...)
              Exit(False);
          end;
          FLastError:= LIBSSH2_ERROR_EAGAIN;
          Continue;
        end;
        // An existing read-only target (e.g. a git object file) refuses the
        // open. When allowed, make it owner-writable once and open it again;
        // the source's mode is put back after the transfer.
        if FOverwriteReadOnly and (not MadeWritable) and
           (FLastError = LIBSSH2_ERROR_SFTP_PROTOCOL) and
           (libssh2_sftp_last_error(FSFTPSession) = LIBSSH2_FX_PERMISSION_DENIED) and
           SetRemoteMode(OpenMode or $80) then
        begin
          MadeWritable:= True;
          FLastError:= LIBSSH2_ERROR_EAGAIN;
          Continue;
        end;
        if (FLastError <> LIBSSH2_ERROR_EAGAIN) then Exit(False);
        if (FileSize > 0) then DoProgress((FileSize - TotalBytesToWrite) * 100 div FileSize);
        FSock.CanRead(10);
      end;
    until not ((TargetHandle = nil) and (FLastError = LIBSSH2_ERROR_EAGAIN));

    BytesToRead:= WRITE_BUFFER_SIZE;
    while (TotalBytesToWrite > 0) do
    begin
      if (BytesToRead > TotalBytesToWrite) then begin
        BytesToRead:= TotalBytesToWrite;
      end;
      BytesRead:= SendStream.Read(FBuffer^, BytesToRead);
      if (BytesRead = 0) then Exit(False);
      // Start write operation
      Index:= 0;
      BytesToWrite:= BytesRead;
      while (BytesToWrite > 0) do
      begin
        repeat
          BytesWritten:= libssh2_sftp_write(TargetHandle, FBuffer + Index, BytesToWrite);
          if BytesWritten = LIBSSH2_ERROR_EAGAIN then begin
            DoProgress((FileSize - TotalBytesToWrite) * 100 div FileSize);
            WaitSocket;
          end;
        until BytesWritten <> LIBSSH2_ERROR_EAGAIN;
        if (BytesWritten < 0) then Exit(False);
        Dec(TotalBytesToWrite, BytesWritten);
        Dec(BytesToWrite, BytesWritten);
        Inc(Index, BytesWritten);
        end;
      DoProgress((FileSize - TotalBytesToWrite) * 100 div FileSize);
    end;
    Result:= True;
  finally
    SendStream.Free;
    FreeMem(FBuffer);
    Result:= FileClose(TargetHandle) and Result;
    libssh2_session_set_blocking(FSession, 1);
    // Opening an existing file does not apply OpenMode, so after making the
    // target writable above set the source's mode explicitly.
    if MadeWritable then SetRemoteMode(OpenMode);
{$IFDEF UNIX}
    // Permissions were already applied at create time (see OpenMode above).
    // Only restore ownership, and only when we are root: for a normal user this
    // setstat always fails on the server, wasting a round-trip on every file.
    if Result and (fpGetEUID = 0) then
    begin
      if FpStat(FDirectFileName, LocalStat) = 0 then
      begin
        FillChar(UploadAttrs, SizeOf(UploadAttrs), 0);
        UploadAttrs.uid:= LocalStat.st_uid;
        UploadAttrs.gid:= LocalStat.st_gid;
        UploadAttrs.flags:= LIBSSH2_SFTP_ATTR_UIDGID;
        libssh2_sftp_setstat(FSFTPSession, PAnsiChar(FileName), @UploadAttrs);
      end;
    end;
{$ENDIF}
  end;
end;

{$IFDEF UNIX}
function TSftpSend.RetrieveLink(const FileName: String): Boolean;
var
  ALength: cint;
  LinkTarget: String;
  ATarget: array[0..1023] of AnsiChar;
begin
  repeat
    ALength:= libssh2_sftp_readlink(FSFTPSession, PAnsiChar(FileName),
                                    ATarget, SizeOf(ATarget));
    if ALength = LIBSSH2_ERROR_EAGAIN then FSock.CanRead(10);
  until ALength <> LIBSSH2_ERROR_EAGAIN;
  // Not a link after all, unreadable, or a target longer than the buffer.
  if (ALength <= 0) then Exit(False);

  SetString(LinkTarget, ATarget, ALength);
  LinkTarget:= CeUtf16ToUtf8(ServerToClient(LinkTarget));

  // fpSymlink does not overwrite, and a dangling link left over from an earlier
  // run is invisible to the caller's FileExists check, so always clear the way.
  fpUnlink(FDirectFileName);
  Result:= fpSymlink(PAnsiChar(LinkTarget), PAnsiChar(FDirectFileName)) = 0;
end;
{$ENDIF}

function TSftpSend.RetrieveFile(const FileName: string; FileSize: Int64;
  Restore: Boolean): Boolean;
var
  FBuffer: PByte;
  BytesRead: PtrInt;
  BytesToRead: csize_t;
  RetrStream: TFileStreamEx;
  TotalBytesToRead: Int64 = 0;
  SourceHandle: PLIBSSH2_SFTP_HANDLE;
{$IFDEF UNIX}
  DownloadAttrs: LIBSSH2_SFTP_ATTRIBUTES;
{$ENDIF}
begin
  if FCopySCP then begin
    Result:= inherited RetrieveFile(FileName, FileSize, Restore);
    Exit;
  end;

{$IFDEF UNIX}
  // The user chose not to follow this link, so copy the link itself. Without
  // this the server resolves it on open and we store a full copy of the target
  // (and for a link to a directory the download fails outright).
  // On failure fall through to a normal content download.
  if FSourceIsLink and RetrieveLink(FileName) then Exit(True);
{$ENDIF}

  if Restore and mbFileExists(FDirectFileName) then
    RetrStream := TFileStreamEx.Create(FDirectFileName, fmOpenWrite or fmShareExclusive)
  else begin
    RetrStream := TFileStreamEx.Create(FDirectFileName, fmCreate or fmShareDenyWrite)
  end;

  SourceName := PWideChar(ServerToClient(FileName));
  TargetName := PWideChar(CeUtf8ToUtf16(FDirectFileName));

  if Restore then TotalBytesToRead:= RetrStream.Seek(0, soEnd);

  libssh2_session_set_blocking(FSession, 0);
  try
    repeat
      SourceHandle:= libssh2_sftp_open(FSFTPSession,
                                       PAnsiChar(FileName),
                                       LIBSSH2_FXF_READ, 0);
      if (SourceHandle = nil) then
      begin
        FLastError:= libssh2_session_last_errno(FSession);
        if (FLastError <> LIBSSH2_ERROR_EAGAIN) then Exit(False);
        if (FileSize > 0) then DoProgress(TotalBytesToRead * 100 div FileSize);
        FSock.CanRead(10);
      end;
    until not ((SourceHandle = nil) and (FLastError = LIBSSH2_ERROR_EAGAIN));

    if Restore then begin
      libssh2_sftp_seek64(SourceHandle, TotalBytesToRead);
    end;

    FBuffer:= GetMem(READ_BUFFER_SIZE);
    TotalBytesToRead:= FileSize - TotalBytesToRead;
    BytesToRead:= READ_BUFFER_SIZE;
    try
      while TotalBytesToRead > 0 do
      begin
        // Never ask for more than the caller said is left. The stream and
        // FileSize can disagree - a symlink reports its own size while the
        // server opens the target - and reading a whole buffer regardless used
        // to drive the counter negative, ending the loop with a truncated file
        // written and success reported.
        if (TotalBytesToRead < BytesToRead) then BytesToRead:= TotalBytesToRead;
        repeat
          BytesRead := libssh2_sftp_read(SourceHandle, PAnsiChar(FBuffer), BytesToRead);
          if BytesRead = LIBSSH2_ERROR_EAGAIN then begin
            DoProgress((FileSize - TotalBytesToRead) * 100 div FileSize);
            FSock.CanRead(10);
          end;
        until BytesRead <> LIBSSH2_ERROR_EAGAIN;

        if (BytesRead < 0) then Exit(False);
        // End of file before FileSize bytes arrived. Fail rather than leave a
        // short file behind and call it a success; without this the loop would
        // also spin forever, since the counter never reaches zero.
        if (BytesRead = 0) then Exit(False);

        if RetrStream.Write(FBuffer^, BytesRead) <> BytesRead then
          Exit(False);

        Dec(TotalBytesToRead, BytesRead);
        DoProgress((FileSize - TotalBytesToRead) * 100 div FileSize);
      end;
      Result:= True;
    finally
      FreeMem(FBuffer);
      Result:= FileClose(SourceHandle) and Result;
    end;
  finally
    RetrStream.Free;
    libssh2_session_set_blocking(FSession, 1);
{$IFDEF UNIX}
    if Result then
    begin
      if libssh2_sftp_stat(FSFTPSession, PAnsiChar(FileName), @DownloadAttrs) = 0 then
      begin
        if (DownloadAttrs.flags and LIBSSH2_SFTP_ATTR_PERMISSIONS) <> 0 then
          FpChmod(FDirectFileName, DownloadAttrs.permissions and $0FFF);
        // Only root can restore ownership; for a normal user this always fails,
        // so skip the syscall (mirrors what StoreFile does for uploads).
        if (fpGetEUID = 0) and ((DownloadAttrs.flags and LIBSSH2_SFTP_ATTR_UIDGID) <> 0) then
          FpChown(FDirectFileName, DownloadAttrs.uid, DownloadAttrs.gid);
      end;
    end;
{$ENDIF}
  end;
end;

function TSftpSend.FsFindFirstW(const Path: String; var FindData: TWin32FindDataW): Pointer;
var
  I: Integer;
  Key: String;
  FindRec: PFindRec;
  Listing: TDirListing;
begin
  if FPrefetch then
  begin
    Key:= Path;
    if (Key = '') or (Key[Length(Key)] <> '/') then Key:= Key + '/';
    I:= FPrefetchCache.IndexOf(Key);
    if I < 0 then
    begin
      // Not fetched yet: fetch it first, and more alongside it
      if FPrefetchSeen.IndexOf(Key) < 0 then FPrefetchSeen.Add(Key);
      I:= FPrefetchPending.IndexOf(Key);
      if I >= 0 then FPrefetchPending.Delete(I);
      Prefetch(Key);
    end
    else if (FPrefetchCache.Count <= PREFETCH_LOW) and (FPrefetchPending.Count > 0) then
      // Top up before the compare runs out of fetched directories
      Prefetch('');
    I:= FPrefetchCache.IndexOf(Key);
    if I >= 0 then
    begin
      // Each directory is listed once per compare: hand the listing over
      Listing:= TDirListing(FPrefetchCache.Objects[I]);
      FPrefetchCache.Delete(I);
      FFindFailed:= Listing.Failed;
      if Listing.Failed or (Listing.Count = 0) then
      begin
        Listing.Free;
        Exit(nil);
      end;
      New(FindRec);
      FindRec.Path:= Key;
      FindRec.Handle:= nil;
      FindRec.Listing:= Listing;
      FindRec.Index:= 0;
      FsFindNextW(FindRec, FindData);
      Exit(FindRec);
    end;
  end;

  Result := libssh2_sftp_opendir(FSFTPSession, PAnsiChar(Path));
  FFindFailed:= (Result = nil);
  if (Result = nil) then
    PrintLastError
  else begin
    New(FindRec);
    FindRec.Path:= Path;
    FindRec.Handle:= Result;
    FindRec.Listing:= nil;
    // Prime the first entry. If the directory has none (some servers, e.g. the
    // Windows OpenSSH SFTP server, do not return '.'/'..' for an empty folder),
    // FindData is left unset; return an invalid handle so the caller does not
    // present that unfilled entry as a phantom file.
    if FsFindNextW(FindRec, FindData) then
      Result:= FindRec
    else begin
      libssh2_sftp_closedir(FindRec.Handle);
      Dispose(FindRec);
      Result:= nil;
    end;
  end;
end;

function TSftpSend.FsFindNextW(Handle: Pointer; var FindData: TWin32FindDataW): BOOL;
var
  Return: Integer;
  FindRec: PFindRec absolute Handle;
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
  LinkTarget: LIBSSH2_SFTP_ATTRIBUTES;
  AFileName: array[0..1023] of AnsiChar;
  AFullData: array[0..2047] of AnsiChar;
begin
  if Assigned(FindRec.Listing) then
  begin
    Result:= FindRec.Index < FindRec.Listing.Count;
    if Result then
    begin
      with FindRec.Listing.Entries[FindRec.Index] do
        if HasTarget then
          FillFindData(Name, Attributes, @Target, FindData)
        else
          FillFindData(Name, Attributes, nil, FindData);
      Inc(FindRec.Index);
    end;
    Exit;
  end;
  Return:= libssh2_sftp_readdir_ex(FindRec.Handle, AFileName, SizeOf(AFileName),
                                   AFullData, SizeOf(AFullData), @Attributes);
  Result:= (Return > 0);
  if Result then
  begin
    // Follow a link to detect whether the target is a directory
    if IsLink(Attributes) and
       (libssh2_sftp_stat(FSFTPSession, PAnsiChar(FindRec.Path + AFileName), @LinkTarget) = 0) then
      FillFindData(AFileName, Attributes, @LinkTarget, FindData)
    else
      FillFindData(AFileName, Attributes, nil, FindData);
  end;
end;

procedure TSftpSend.FillFindData(const AName: String;
  const Attributes: LIBSSH2_SFTP_ATTRIBUTES; LinkTarget: PLIBSSH2_SFTP_ATTRIBUTES;
  var FindData: TWin32FindDataW);
begin
  FillChar(FindData, SizeOf(FindData), 0);
  FindData.dwReserved0:= Attributes.permissions;
  FindData.dwFileAttributes:= FILE_ATTRIBUTE_UNIX_MODE;
  // A symlink keeps its own mtime and size (the length of the link target
  // string) for sync comparisons.
  if (Attributes.permissions and S_IFMT) <> S_IFDIR then
  begin
    FindData.nFileSizeLow:= Int64Rec(Attributes.filesize).Lo;
    FindData.nFileSizeHigh:= Int64Rec(Attributes.filesize).Hi;
  end;
  StrPLCopy(FindData.cFileName, ServerToClient(AName), MAX_PATH - 1);
  FindData.ftLastWriteTime:= TWfxFileTime(UnixFileTimeToWinTime(Attributes.mtime));
  FindData.ftLastAccessTime:= TWfxFileTime(UnixFileTimeToWinTime(Attributes.atime));
  // LinkTarget: the stat'ed target of a symlink, nil if it could not be read.
  // A link to a directory is flagged as such but keeps its own size (the
  // length of its target text) like any other link: sync compares links by it.
  if IsLink(Attributes) and Assigned(LinkTarget) and
     ((LinkTarget^.permissions and S_IFMT) = S_IFDIR) then
    FindData.dwFileAttributes:= FindData.dwFileAttributes or FILE_ATTRIBUTE_REPARSE_POINT;
end;

function TSftpSend.FsFindClose(Handle: Pointer): Integer;
var
  FindRec: PFindRec absolute Handle;
begin
  if Assigned(FindRec.Listing) then
  begin
    FindRec.Listing.Free;
    Result:= 0;
  end
  else
    Result:= libssh2_sftp_closedir(FindRec.Handle);
  Dispose(FindRec);
end;

function TSftpSend.FsSetTime(const FileName: String; LastAccessTime,
  LastWriteTime: WfxPlugin.PFileTime): BOOL;
var
  Attributes: LIBSSH2_SFTP_ATTRIBUTES;
begin
  if (LastAccessTime = nil) or (LastWriteTime = nil) then
  begin
    if libssh2_sftp_stat(FSFTPSession, PAnsiChar(FileName), @Attributes) <> 0 then
      Exit(False);
  end;
  if Assigned(LastAccessTime) then begin
    Attributes.atime:= WinFileTimeToUnixTime(TWinFileTime(LastAccessTime^));
  end;
  if Assigned(LastWriteTime) then begin
    Attributes.mtime:= WinFileTimeToUnixTime(TWinFileTime(LastWriteTime^));
  end;
  Attributes.flags:= LIBSSH2_SFTP_ATTR_ACMODTIME;
  Result:= libssh2_sftp_setstat(FSFTPSession, PAnsiChar(FileName), @Attributes) = 0;
end;

end.

