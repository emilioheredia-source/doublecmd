unit SftpGunzip;

{
  Unpacks a gzip stream that arrives in pieces, as `gzip` writes it to a
  pipe: one member, read as the bytes come in. The gzip header is read here;
  the deflate data in between goes to the zlib port that comes with Free
  Pascal (paszlib), so no zlib library is needed at run time.
}

{$mode objfpc}{$H+}

interface

uses
  zbase;

type

  { TGunzip }

  TGunzip = class
  private
    FStream: z_stream;
    FHeader: String;          // header bytes gathered so far
    FInHeader: Boolean;
    FStarted: Boolean;        // inflate initialized
    FEnded: Boolean;          // the deflate data is complete
    function TakeHeader(var Data: PByte; var Count: Integer): Boolean;
    function Inflate(Data: PByte; Count: Integer; var Output: String): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    // Appends what Data unpacks to Output. False when the stream is not
    // valid gzip.
    function Feed(Data: PByte; Count: Integer; var Output: String): Boolean;
    // The compressed data ended properly; what follows is the trailer
    property Ended: Boolean read FEnded;
  end;

// True if S starts like a gzip stream
function LooksLikeGzip(const S: String): Boolean;

implementation

uses
  zinflate;

const
  GZIP_ID = #$1F#$8B;
  DEFLATE = 8;
  // Header flags
  FLAG_HCRC = 2;
  FLAG_EXTRA = 4;
  FLAG_NAME = 8;
  FLAG_COMMENT = 16;
  // Bytes unpacked per inflate call
  OUTPUT_CHUNK = 65536;

function LooksLikeGzip(const S: String): Boolean;
begin
  Result:= System.Copy(S, 1, 2) = GZIP_ID;   // zbase has a COPY too
end;

// The header's optional fields are skipped with these. P is where a field
// starts; each returns where the next one starts, or 0 while the field is
// not complete yet (and passes a 0 on).

function SkipBytes(const H: String; P, Count: Integer): Integer;
begin
  if (P = 0) or (P + Count - 1 > Length(H)) then Exit(0);
  Result:= P + Count;
end;

function SkipZeroTerminated(const H: String; P: Integer): Integer;
begin
  if P = 0 then Exit(0);
  while (P <= Length(H)) and (H[P] <> #0) do Inc(P);
  if P > Length(H) then Exit(0);
  Result:= P + 1;
end;

// Two bytes of length, then the data
function SkipExtraField(const H: String; P: Integer): Integer;
begin
  if SkipBytes(H, P, 2) = 0 then Exit(0);
  Result:= SkipBytes(H, P, 2 + Ord(H[P]) + Ord(H[P + 1]) * 256);
end;

// The header's length; 0 while more bytes are needed, -1 if it is not gzip
function HeaderLength(const H: String): Integer;
var
  Flags: Byte;
  P: Integer;
begin
  if Length(H) < 10 then Exit(0);
  if not LooksLikeGzip(H) or (Ord(H[3]) <> DEFLATE) then Exit(-1);
  Flags:= Ord(H[4]);
  P:= 11;
  if Flags and FLAG_EXTRA <> 0 then P:= SkipExtraField(H, P);
  if Flags and FLAG_NAME <> 0 then P:= SkipZeroTerminated(H, P);
  if Flags and FLAG_COMMENT <> 0 then P:= SkipZeroTerminated(H, P);
  if Flags and FLAG_HCRC <> 0 then P:= SkipBytes(H, P, 2);
  if P = 0 then Exit(0);
  Result:= P - 1;
end;

{ TGunzip }

constructor TGunzip.Create;
begin
  FInHeader:= True;
end;

destructor TGunzip.Destroy;
begin
  if FStarted then inflateEnd(FStream);
  inherited Destroy;
end;

function TGunzip.Feed(Data: PByte; Count: Integer; var Output: String): Boolean;
begin
  if FEnded then Exit(True);   // the trailer: checksum and size
  if FInHeader and not TakeHeader(Data, Count) then Exit(False);
  if FInHeader or (Count = 0) then Exit(True);
  Result:= Inflate(Data, Count, Output);
end;

// Gathers the header; on return Data/Count are what follows it
function TGunzip.TakeHeader(var Data: PByte; var Count: Integer): Boolean;
var
  Len, Before: Integer;
begin
  Before:= Length(FHeader);
  SetLength(FHeader, Before + Count);
  Move(Data^, FHeader[Before + 1], Count);
  Len:= HeaderLength(FHeader);
  if Len < 0 then Exit(False);
  Result:= True;
  if Len = 0 then
  begin
    Count:= 0;
    Exit;
  end;
  // Raw deflate (negative window bits): the header was read here
  Result:= inflateInit2(FStream, -MAX_WBITS) = Z_OK;
  FStarted:= Result;
  FInHeader:= False;
  Inc(Data, Len - Before);
  Count:= Length(FHeader) - Len;
end;

function TGunzip.Inflate(Data: PByte; Count: Integer; var Output: String): Boolean;
var
  Len, Rc: Integer;
begin
  FStream.next_in:= Data;
  FStream.avail_in:= Count;
  repeat
    Len:= Length(Output);
    SetLength(Output, Len + OUTPUT_CHUNK);
    FStream.next_out:= @Output[Len + 1];
    FStream.avail_out:= OUTPUT_CHUNK;
    Rc:= zinflate.inflate(FStream, Z_NO_FLUSH);
    SetLength(Output, Len + OUTPUT_CHUNK - Integer(FStream.avail_out));
    FEnded:= Rc = Z_STREAM_END;
    // Z_BUF_ERROR: nothing more to do until more input arrives
    if FEnded or (Rc = Z_BUF_ERROR) then Exit(True);
    if Rc <> Z_OK then Exit(False);
  until (FStream.avail_in = 0) and (FStream.avail_out > 0);
  Result:= True;
end;

end.
