unit SftpTreeList;

{
  Directory listings read ahead of a sync compare, and the fast way to get
  all of them at once.

  A sync compare lists every remote directory, and SFTP needs a few round
  trips per directory. TFindTreeLister instead runs one GNU find on the
  server over an exec channel and builds the same listings from its output.
  It is used only where it gives exactly what SFTP gives: on any doubt (no
  command allowed, no GNU find, an error, too slow, the shell seeing another
  tree than SFTP) Run returns False with a Reason, nothing is kept, and the
  caller lists directory by directory as before.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CTypes, contnrs, libssh, SftpGunzip;

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

  // Waits until the session's socket is ready in the direction libssh2 needs
  TWaitProc = procedure of object;
  // False when the caller wants the listing stopped
  TAskContinueFunc = function: Boolean of object;

  { TFindTreeLister }

  TFindTreeLister = class
  private
    FSession: PLIBSSH2_SESSION;
    FSftp: PLIBSSH2_SFTP;
    FWait: TWaitProc;
    FAskContinue: TAskContinueFunc;
    FBase: String;               // the tree's root, with a trailing '/'
    // Listings in find's order (keyed by path + '/'), and by key; sorted
    // once at the end
    FDirs: TStringList;
    FDirByKey: TFPObjectHashTable;
    FUnreadable: TStringList;    // paths, relative to the root, find did not enter
    FRootParent: LIBSSH2_SFTP_ATTRIBUTES;
    FHaveRootParent: Boolean;
    FSeenRoot: Boolean;
    FGivenUp: Boolean;           // the command is not waited for any more
    FEntries: Integer;
    FFindEnded: Boolean;         // find's exit status, the last record, arrived
    FFindStatus: Integer;
    FFormatKnown: Boolean;       // compressed or not, seen from the first bytes
    FFirstBytes: String;
    FGunzip: TGunzip;            // assigned when the output is compressed
    FReason: String;
    FStartTime, FLastData, FLastAsked: QWord;
    function Fail(const Why: String): Boolean;
    function KeepGoing: Boolean;
    function WaitMore: Boolean;
    function Command: String;
    function StartCommand: PLIBSSH2_CHANNEL;
    function ReadOutput(Channel: PLIBSSH2_CHANNEL): Boolean;
    function AddOutput(Data: PByte; Count: Integer; var Pending: String): Boolean;
    function TakeRecords(var Pending: String): Boolean;
    function AddRecord(const Rec: String): Boolean;
    function AddRoot(const Attrs: LIBSSH2_SFTP_ATTRIBUTES; Kind: Char): Boolean;
    procedure AddEntry(const RelPath: String; Kind: Char; LinkTarget: culong;
      const Attrs: LIBSSH2_SFTP_ATTRIBUTES);
    procedure NewListing(const Key: String; const Own, Parent: LIBSSH2_SFTP_ATTRIBUTES);
    function DirKey(const RelPath: String): String;
    function FindListing(const Key: String): TDirListing;
    function WaitForExit(Channel: PLIBSSH2_CHANNEL): Boolean;
    function OutputIsComplete: Boolean;
    function RootIsComplete: Boolean;
    function RootMatchesSftp: Boolean;
    function CountSftpMatches(Handle: PLIBSSH2_SFTP_HANDLE; Root: TDirListing): Integer;
    function GetMilliseconds: QWord;
    function GetCompressed: Boolean;
  public
    // Base: the tree's root in server encoding, ending with '/'. Wait is
    // called whenever libssh2 would block.
    constructor Create(Session: PLIBSSH2_SESSION; Sftp: PLIBSSH2_SFTP;
      Wait: TWaitProc; const Base: String);
    destructor Destroy; override;
    // Lists the whole tree. False, with Reason set, when that is not possible.
    function Run: Boolean;
    // Hands the listings over, keyed by path with a trailing '/'
    procedure MoveListingsTo(Cache, Seen: TStringList);
    // Asked about ten times a second while find runs
    property OnAskContinue: TAskContinueFunc read FAskContinue write FAskContinue;
    property Reason: String read FReason;
    property EntryCount: Integer read FEntries;
    property Milliseconds: QWord read GetMilliseconds;
    // The server compressed the listing (it has gzip)
    property Compressed: Boolean read GetCompressed;
  end;

implementation

uses
  StrUtils, DCFileAttributes;

const
  // Beyond this many entries the listing costs too much memory
  MAX_ENTRIES = 1000000;
  // DC waits while find runs and cannot cancel it: give up after this long
  // without data (ms), or in all
  IDLE_LIMIT = 20000;
  TOTAL_LIMIT = 90000;
  // How often (ms) the caller is asked whether to go on
  ASK_INTERVAL = 100;

  UNEXPECTED_OUTPUT = 'unexpected output (no GNU find?)';
  NO_COMMAND = 'the server allows no command';

type
  // One line of find's output, see TFindTreeLister.Command
  TFindRecord = record
    Unreadable: Boolean;         // a directory find could not enter
    Kind: Char;                  // find's %y: f d l b c p s
    LinkTarget: culong;          // a symlink's target type bits, 0 if none
    Attrs: LIBSSH2_SFTP_ATTRIBUTES;
    RelPath: String;             // relative to the root, '' for the root
  end;

function TypeBits(C: Char): culong;
begin
  case C of
    'f': Result:= S_IFREG;
    'd': Result:= S_IFDIR;
    'l': Result:= S_IFLNK;
    'b': Result:= S_IFBLK;
    'c': Result:= S_IFCHR;
    'p': Result:= S_IFIFO;
    's': Result:= S_IFSOCK;
  else
    Result:= 0;   // 'N' missing target, 'L' loop, '?' unknown
  end;
end;

// The space-separated field of S starting at P; P moves past it
function NextField(const S: String; var P: Integer): String;
var
  Q: Integer;
begin
  Q:= P;
  while (Q <= Length(S)) and (S[Q] <> ' ') do Inc(Q);
  Result:= Copy(S, P, Q - P);
  P:= Q + 1;
end;

function ParseOctal(const S: String; out Value: culong): Boolean;
var
  I: Integer;
begin
  Value:= 0;
  Result:= S <> '';
  for I:= 1 to Length(S) do
  begin
    if not (S[I] in ['0'..'7']) then Exit(False);
    Value:= Value * 8 + culong(Ord(S[I]) - Ord('0'));
  end;
end;

// Whole seconds of find's "seconds.fraction"
function ParseSeconds(const S: String; out Value: culong): Boolean;
var
  Seconds: Int64;
begin
  Result:= TryStrToInt64(Copy(S, 1, Pos('.', S + '.') - 1), Seconds);
  Value:= culong(Seconds);
end;

procedure AppendBytes(var S: String; const Buffer; Count: Integer);
var
  Len: Integer;
begin
  Len:= Length(S);
  SetLength(S, Len + Count);
  Move(Buffer, S[Len + 1], Count);
end;

function ShellQuote(const S: String): String;
begin
  Result:= '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

// "U path" or "type target-type mode size mtime atime path"
function ParseFindRecord(const Rec: String; out R: TFindRecord): Boolean;
var
  P: Integer;
  Kind, LinkKind, Mode, Size, MTime, ATime: String;
  Bits: culong;
begin
  R:= Default(TFindRecord);
  R.Unreadable:= Copy(Rec, 1, 2) = 'U ';
  if R.Unreadable then
  begin
    R.RelPath:= Copy(Rec, 3, MaxInt);
    Exit(True);
  end;
  P:= 1;
  Kind:= NextField(Rec, P); LinkKind:= NextField(Rec, P); Mode:= NextField(Rec, P);
  Size:= NextField(Rec, P); MTime:= NextField(Rec, P); ATime:= NextField(Rec, P);
  R.RelPath:= Copy(Rec, P, MaxInt);
  Result:= (Length(Kind) = 1) and (Length(LinkKind) = 1) and ParseOctal(Mode, Bits) and
           TryStrToQWord(Size, R.Attrs.filesize) and
           ParseSeconds(MTime, R.Attrs.mtime) and ParseSeconds(ATime, R.Attrs.atime);
  if not Result then Exit;
  R.Kind:= Kind[1];
  if R.Kind = 'l' then R.LinkTarget:= TypeBits(LinkKind[1]);
  R.Attrs.flags:= LIBSSH2_SFTP_ATTR_SIZE or LIBSSH2_SFTP_ATTR_PERMISSIONS or
                  LIBSSH2_SFTP_ATTR_ACMODTIME;
  R.Attrs.permissions:= TypeBits(R.Kind) or Bits;
end;

function SameAttributes(const A, B: LIBSSH2_SFTP_ATTRIBUTES): Boolean;
begin
  Result:= (A.permissions = B.permissions) and (A.filesize = B.filesize) and
           (A.mtime = B.mtime);
end;

// Name -> entry index
function IndexByName(Listing: TDirListing): TStringList;
var
  I: Integer;
begin
  Result:= TStringList.Create;
  Result.Sorted:= True;
  Result.CaseSensitive:= True;
  for I:= 0 to Listing.Count - 1 do
    Result.AddObject(Listing.Entries[I].Name, TObject(PtrInt(I)));
end;

function IsDot(const Name: String): Boolean;
begin
  Result:= (Name = '.') or (Name = '..');
end;

// Paths compared byte by byte: the locale's collation is not needed for
// exact lookups and is many times slower
function CreatePathList(Sorted: Boolean = True): TStringList;
begin
  Result:= TStringList.Create;
  Result.UseLocale:= False;
  Result.CaseSensitive:= True;
  Result.Sorted:= Sorted;
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

{ TFindTreeLister }

constructor TFindTreeLister.Create(Session: PLIBSSH2_SESSION; Sftp: PLIBSSH2_SFTP;
  Wait: TWaitProc; const Base: String);
begin
  FSession:= Session;
  FSftp:= Sftp;
  FWait:= Wait;
  FBase:= Base;
  FDirs:= CreatePathList(False);
  FDirByKey:= TFPObjectHashTable.Create(False);
  FUnreadable:= CreatePathList;
end;

destructor TFindTreeLister.Destroy;
var
  I: Integer;
begin
  for I:= 0 to FDirs.Count - 1 do
    FDirs.Objects[I].Free;
  FDirs.Free;
  FDirByKey.Free;
  FUnreadable.Free;
  FGunzip.Free;
  inherited Destroy;
end;

function TFindTreeLister.Run: Boolean;
var
  Channel: PLIBSSH2_CHANNEL;
begin
  FStartTime:= GetTickCount64;
  if not EndsStr('/', FBase) then Exit(Fail('no tree root'));
  FHaveRootParent:= libssh2_sftp_lstat(FSftp, PAnsiChar(FBase + '..'), @FRootParent) = 0;
  Channel:= StartCommand;
  if Channel = nil then Exit(False);
  try
    // Non-blocking, so a command that hangs can be given up on
    libssh2_session_set_blocking(FSession, 0);
    Result:= ReadOutput(Channel) and WaitForExit(Channel);
    if not FGivenUp then libssh2_session_set_blocking(FSession, 1);
    Result:= Result and OutputIsComplete and RootIsComplete and RootMatchesSftp;
  finally
    // Given up on: freed without waiting, the server ends the command
    libssh2_channel_free(Channel);
    libssh2_session_set_blocking(FSession, 1);
  end;
end;

procedure TFindTreeLister.MoveListingsTo(Cache, Seen: TStringList);
var
  I: Integer;
begin
  // In order, each lands at the end of the sorted lists
  FDirs.Sort;
  for I:= 0 to FDirs.Count - 1 do
  begin
    Cache.AddObject(FDirs[I], FDirs.Objects[I]);
    Seen.Add(FDirs[I]);
  end;
  FDirs.Clear;
end;

function TFindTreeLister.Fail(const Why: String): Boolean;
begin
  if FReason = '' then FReason:= Why;
  Result:= False;
end;

function TFindTreeLister.KeepGoing: Boolean;
begin
  Result:= True;
  if not Assigned(FAskContinue) or (GetTickCount64 - FLastAsked < ASK_INTERVAL) then Exit;
  FLastAsked:= GetTickCount64;
  Result:= FAskContinue();
  if not Result then
  begin
    FGivenUp:= True;
    Fail('cancelled');
  end;
end;

// Waits for the socket if there is time left; else gives up
function TFindTreeLister.WaitMore: Boolean;
begin
  if not KeepGoing then Exit(False);
  Result:= (GetTickCount64 - FLastData <= IDLE_LIMIT) and
           (GetTickCount64 - FStartTime <= TOTAL_LIMIT);
  if Result then
    FWait
  else begin
    FGivenUp:= True;
    Fail('it took too long');
  end;
end;

function TFindTreeLister.Command: String;
var
  Root, Find: String;
begin
  Root:= FBase;
  if Root <> '/' then Delete(Root, Length(Root), 1);
  // -H follows a root that is a symlink, as SFTP does. Directories that
  // cannot be listed are reported and not entered, so find has nothing to
  // complain about and its exit status tells whether the listing is whole.
  Find:= 'env LC_ALL=C find -H ' + ShellQuote(Root) +
         ' \( -type d -not \( -readable -executable \) -printf ''U %P\0'' -prune \)' +
         ' , -printf ''%y %Y %m %s %T@ %A@ %P\0''';
  // Run by sh, whatever the login shell. A pipe's status is its last
  // command's, so find's status follows its output as a last record; the
  // output is compressed where the server has gzip.
  Result:= 'sh -c ' + ShellQuote('{ ' + Find + '; printf ''E %d\0'' $?; } | ' +
           'if command -v gzip >/dev/null 2>&1; then gzip -1; else cat; fi');
end;

function TFindTreeLister.StartCommand: PLIBSSH2_CHANNEL;
begin
  Result:= libssh2_channel_open_session(FSession);
  if Result = nil then
  begin
    Fail(NO_COMMAND);
    Exit;
  end;
  libssh2_channel_handle_extended_data2(Result, LIBSSH2_CHANNEL_EXTENDED_DATA_IGNORE);
  if libssh2_channel_exec(Result, PAnsiChar(Command)) <> 0 then
  begin
    Fail(NO_COMMAND);
    libssh2_channel_free(Result);
    Exit(nil);
  end;
  // Nothing to send. On an account limited to SFTP every command starts the
  // SFTP server, which would otherwise wait for input forever.
  libssh2_channel_send_eof(Result);
end;

function TFindTreeLister.ReadOutput(Channel: PLIBSSH2_CHANNEL): Boolean;
var
  Buffer: array[0..65535] of AnsiChar;
  Pending: String = '';
  Rc: ptrint;
begin
  FLastData:= GetTickCount64;
  repeat
    Rc:= libssh2_channel_read(Channel, @Buffer[0], SizeOf(Buffer));
    // Non-blocking, a read can return 0 before the end: only the channel's
    // end-of-file is the end
    if (Rc = LIBSSH2_ERROR_EAGAIN) or ((Rc = 0) and (libssh2_channel_eof(Channel) = 0)) then
    begin
      if not WaitMore then Exit(False);
      Continue;
    end;
    if Rc <= 0 then Break;
    FLastData:= GetTickCount64;
    if not (AddOutput(@Buffer[0], Rc, Pending) and TakeRecords(Pending)) then
    begin
      // Stop it: waiting for the end of an unwanted listing helps no one
      FGivenUp:= True;
      Exit(False);
    end;
    if not KeepGoing then Exit(False);
  until False;
  if Rc < 0 then Exit(Fail('reading its output failed'));
  Result:= (Pending = '') or Fail(UNEXPECTED_OUTPUT);
end;

// Appends the received bytes to Pending, unpacked if the server compressed them
function TFindTreeLister.AddOutput(Data: PByte; Count: Integer; var Pending: String): Boolean;
var
  First: String;
begin
  if not FFormatKnown then
  begin
    // gzip shows in the first two bytes
    AppendBytes(FFirstBytes, Data^, Count);
    if Length(FFirstBytes) < 2 then Exit(True);
    FFormatKnown:= True;
    if LooksLikeGzip(FFirstBytes) then FGunzip:= TGunzip.Create;
    First:= FFirstBytes;
    FFirstBytes:= '';
    Data:= PByte(First);
    Count:= Length(First);
  end;
  if Assigned(FGunzip) then
    Exit(FGunzip.Feed(Data, Count, Pending) or Fail(UNEXPECTED_OUTPUT));
  AppendBytes(Pending, Data^, Count);
  Result:= True;
end;

function TFindTreeLister.TakeRecords(var Pending: String): Boolean;
var
  Start, Stop: Integer;
begin
  Result:= True;
  Start:= 1;
  Stop:= PosEx(#0, Pending, Start);
  while Result and (Stop > 0) do
  begin
    Result:= AddRecord(Copy(Pending, Start, Stop - Start));
    Start:= Stop + 1;
    Stop:= PosEx(#0, Pending, Start);
  end;
  Delete(Pending, 1, Start - 1);
end;

function TFindTreeLister.AddRecord(const Rec: String): Boolean;
var
  R: TFindRecord;
begin
  if FFindEnded then Exit(Fail(UNEXPECTED_OUTPUT));
  if Copy(Rec, 1, 2) = 'E ' then
  begin
    FFindEnded:= True;
    FFindStatus:= StrToIntDef(Copy(Rec, 3, MaxInt), -1);
    Exit(True);
  end;
  if not ParseFindRecord(Rec, R) then Exit(Fail(UNEXPECTED_OUTPUT));
  if R.Unreadable then
  begin
    FUnreadable.Add(R.RelPath);
    Exit(True);
  end;
  if R.RelPath = '' then Exit(AddRoot(R.Attrs, R.Kind));
  if not FSeenRoot then Exit(Fail(UNEXPECTED_OUTPUT));
  AddEntry(R.RelPath, R.Kind, R.LinkTarget, R.Attrs);
  Inc(FEntries);
  Result:= (FEntries <= MAX_ENTRIES) or Fail(Format('more than %d entries', [MAX_ENTRIES]));
end;

// The root comes first, once, and is a directory
function TFindTreeLister.AddRoot(const Attrs: LIBSSH2_SFTP_ATTRIBUTES; Kind: Char): Boolean;
begin
  if FSeenRoot or (Kind <> 'd') then Exit(Fail(UNEXPECTED_OUTPUT));
  FSeenRoot:= True;
  if not FHaveRootParent then FRootParent:= Attrs;
  if FUnreadable.IndexOf('') < 0 then NewListing(FBase, Attrs, FRootParent);
  Result:= True;
end;

procedure TFindTreeLister.AddEntry(const RelPath: String; Kind: Char;
  LinkTarget: culong; const Attrs: LIBSSH2_SFTP_ATTRIBUTES);
var
  Parent: TDirListing;
  Slash: Integer;
begin
  Slash:= RPos('/', RelPath);
  Parent:= FindListing(DirKey(Copy(RelPath, 1, Slash - 1)));
  // find lists a directory before its contents: a parent without a listing
  // could not be read, and its entries are not needed
  if Parent = nil then Exit;
  if (Kind = 'd') and (FUnreadable.IndexOf(RelPath) < 0) then
    // Entries[0] is the parent's own '.'
    NewListing(DirKey(RelPath), Attrs, Parent.Entries[0].Attributes);
  Parent.Add(Copy(RelPath, Slash + 1, MaxInt), Attrs);
  if LinkTarget = 0 then Exit;
  with Parent.Entries[Parent.Count - 1] do
  begin
    HasTarget:= True;
    Target.flags:= LIBSSH2_SFTP_ATTR_PERMISSIONS;
    Target.permissions:= LinkTarget;
  end;
end;

// A listing starts with '.' and '..', as a server's does
procedure TFindTreeLister.NewListing(const Key: String; const Own, Parent: LIBSSH2_SFTP_ATTRIBUTES);
var
  Listing: TDirListing;
begin
  Listing:= TDirListing.Create;
  Listing.Path:= Key;
  Listing.Closed:= True;
  Listing.Add('.', Own);
  Listing.Add('..', Parent);
  FDirs.AddObject(Key, Listing);
  FDirByKey.Items[Key]:= Listing;
end;

function TFindTreeLister.FindListing(const Key: String): TDirListing;
begin
  Result:= TDirListing(FDirByKey.Items[Key]);
end;

function TFindTreeLister.DirKey(const RelPath: String): String;
begin
  if RelPath = '' then
    Result:= FBase
  else
    Result:= FBase + RelPath + '/';
end;

// The exit status arrives with the end of the channel
function TFindTreeLister.WaitForExit(Channel: PLIBSSH2_CHANNEL): Boolean;
var
  Status: Integer;
begin
  while libssh2_channel_close(Channel) = LIBSSH2_ERROR_EAGAIN do
    if not WaitMore then Exit(False);
  while libssh2_channel_wait_closed(Channel) = LIBSSH2_ERROR_EAGAIN do
    if not WaitMore then Exit(False);
  Status:= libssh2_channel_get_exit_status(Channel);
  Result:= (Status = 0) or Fail(Format('the command ended with status %d', [Status]));
end;

function TFindTreeLister.OutputIsComplete: Boolean;
begin
  if not FFindEnded or (Assigned(FGunzip) and not FGunzip.Ended) then
    Exit(Fail('its output was cut short'));
  Result:= (FFindStatus = 0) or Fail(Format('find ended with status %d', [FFindStatus]));
end;

function TFindTreeLister.RootIsComplete: Boolean;
begin
  if not FSeenRoot then Exit(Fail(UNEXPECTED_OUTPUT));
  Result:= Assigned(FindListing(FBase)) or Fail('its root cannot be listed');
end;

// The shell and the SFTP server must see the same tree: a server can map
// SFTP paths elsewhere (a chroot, a NAS's shares). The root as SFTP lists it
// has to match find's listing, entry by entry.
function TFindTreeLister.RootMatchesSftp: Boolean;
var
  Root: TDirListing;
  Handle: PLIBSSH2_SFTP_HANDLE;
  Matched: Integer = -1;
begin
  Root:= FindListing(FBase);
  Handle:= libssh2_sftp_opendir(FSftp, PAnsiChar(FBase));
  if Assigned(Handle) then
  try
    Matched:= CountSftpMatches(Handle, Root);
  finally
    libssh2_sftp_closedir(Handle);
  end;
  // Root.Entries[0..1] are '.' and '..', which a server may leave out
  Result:= (Matched = Root.Count - 2) or Fail('the shell does not see the same files as SFTP');
end;

// How many entries other than '.' and '..' SFTP lists the same as find; -1
// at the first difference
function TFindTreeLister.CountSftpMatches(Handle: PLIBSSH2_SFTP_HANDLE;
  Root: TDirListing): Integer;
var
  Names: TStringList;
  Attrs: LIBSSH2_SFTP_ATTRIBUTES;
  AName: array[0..1023] of AnsiChar;
  AFullData: array[0..2047] of AnsiChar;
  Name: String;
  Len, I: Integer;
begin
  Result:= 0;
  Names:= IndexByName(Root);
  try
    repeat
      Len:= libssh2_sftp_readdir_ex(Handle, AName, SizeOf(AName), AFullData, SizeOf(AFullData), @Attrs);
      if Len <= 0 then Break;
      SetString(Name, PAnsiChar(@AName[0]), Len);
      I:= Names.IndexOf(Name);
      if (I < 0) or not SameAttributes(Root.Entries[PtrInt(Names.Objects[I])].Attributes, Attrs) then
        Exit(-1);
      if not IsDot(Name) then Inc(Result);
    until False;
    if Len < 0 then Result:= -1;
  finally
    Names.Free;
  end;
end;

function TFindTreeLister.GetCompressed: Boolean;
begin
  Result:= Assigned(FGunzip);
end;

function TFindTreeLister.GetMilliseconds: QWord;
begin
  Result:= GetTickCount64 - FStartTime;
end;

end.
