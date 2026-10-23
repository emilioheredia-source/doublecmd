unit uSyncDirsView;

{
  The grid rows of the Synchronize directories dialog, by folder.

  The synchronizer works from the row list (TFlatDirFileList): what the state
  filters let through is what gets synchronized. This unit builds what the
  grid shows from that list and the folder tree, so folding a folder or
  hiding files changes the display only, never the sync. A folder row stands
  for every row beneath it, and the dialog maps the selected grid rows back
  to row list indexes before any action is applied.
}

{$mode ObjFPC}{$H+}{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, IntegerList,
  uSyncDirsModel;

type

  { TSyncDirSummary }

  // What a folder holds beneath it, counted over the rows the state filters
  // let through
  TSyncDirSummary = record
    copyToRight, copyToLeft, deleteLeft, deleteRight: Integer;
    conflicts, unreadable, equal, undecided: Integer;
    function total: Integer;
    // Newer files on both sides: the folder that needs a look file by file
    function changedOnBothSides: Boolean;
    // The one action every change beneath shares, or srsDoNothing when mixed
    function singleAction: TSyncRecState;
  end;

  TSyncViewRowKind = ( vrFile, vrFolder, vrFoldedFolder );

  { TSyncViewRow }

  TSyncViewRow = record
    kind: TSyncViewRowKind;
    rec: TSyncRec;                // the file, or the folder's record
    dirIndex: Integer;            // folders: index in the tree
    depth: Integer;               // 1 = top-level folder
    rowIndex: Integer;            // this row's index in the row list; -1 for a folder without one
    rowFirst, rowLast: Integer;   // folders: every row list index beneath
  end;

  { TSyncDirsView }

  TSyncDirsView = class
  private
    type
      TDirInfo = record
        ownRow, fileFirst, fileLast, first, last: Integer;
        summary: TSyncDirSummary;
      end;
  private
    _tree: TTwoLevelTree;
    _rows: TFlatDirFileList;
    _dirs: array of TDirInfo;
    _view: array of TSyncViewRow;
    _count: Integer;
    _level: Integer;                      // fold folders at this depth and below; 0 = never
    _showFiles: Boolean;
    _actionsIncludeSubfolders: Boolean;
    _opened: TFPList;                     // folders opened or closed by hand (TSyncDirRec)
    _closed: TFPList;
    procedure collectRows;
    procedure collectSubtrees;
    procedure emitRows;
    procedure addRow( const row: TSyncViewRow );
    function depthOf( const dirIndex: Integer ): Integer;
    function isFolded( const dirIndex, depth: Integer ): Boolean;
  public
    constructor Create( const tree: TTwoLevelTree; const rows: TFlatDirFileList );
    destructor Destroy; override;

    // After the row list changed, or an action changed
    procedure build;
    // After a new compare: the records folded by hand are gone
    procedure forgetManualFolds;

    function Count: Integer;
    function row( const index: Integer ): TSyncViewRow;
    function summaryOf( const index: Integer ): TSyncDirSummary;
    function rootSummary: TSyncDirSummary;

    procedure toggle( const index: Integer );
    // The row list indexes the selected grid rows stand for
    procedure rowListIndexes( const viewIndexes: TIntegerList; const target: TIntegerList );
    // The last grid row still under the folder row at index (the row itself for a file)
    function lastRowUnder( const index: Integer ): Integer;

    property level: Integer read _level write _level;
    property showFiles: Boolean read _showFiles write _showFiles;
    property actionsIncludeSubfolders: Boolean read _actionsIncludeSubfolders write _actionsIncludeSubfolders;
  end;

implementation

{ TSyncDirSummary }

function TSyncDirSummary.total: Integer;
begin
  Result:= copyToRight + copyToLeft + deleteLeft + deleteRight +
           conflicts + unreadable + equal + undecided;
end;

function TSyncDirSummary.changedOnBothSides: Boolean;
begin
  Result:= (copyToRight > 0) and (copyToLeft > 0);
end;

function TSyncDirSummary.singleAction: TSyncRecState;
var
  kinds: Integer;
begin
  kinds:= Ord(copyToRight > 0) + Ord(copyToLeft > 0) + Ord(deleteLeft > 0) + Ord(deleteRight > 0);
  if (kinds <> 1) or (conflicts > 0) or (unreadable > 0) then
    Exit( srsDoNothing );
  if copyToRight > 0 then Result:= srsCopyToRight
  else if copyToLeft > 0 then Result:= srsCopyToLeft
  else if deleteLeft > 0 then Result:= srsDeleteLeft
  else Result:= srsDeleteRight;
end;

// Where one row counts in its folder's summary
procedure countRow( var summary: TSyncDirSummary; const rec: TSyncRec );
begin
  if rec.isUnreadable then
    Inc( summary.unreadable )
  else if rec.isTypeConflict then
    Inc( summary.conflicts )
  else case rec.action of
    srsCopyToRight: Inc( summary.copyToRight );
    srsCopyToLeft:  Inc( summary.copyToLeft );
    srsDeleteLeft:  Inc( summary.deleteLeft );
    srsDeleteRight: Inc( summary.deleteRight );
    srsDeleteBoth:
      begin
        Inc( summary.deleteLeft );
        Inc( summary.deleteRight );
      end;
    else
      if rec.isFile then begin
        if rec.state = srsEqual then
          Inc( summary.equal )
        else
          Inc( summary.undecided );
      end;
  end;
end;

procedure addSummary( var summary: TSyncDirSummary; const other: TSyncDirSummary );
begin
  Inc( summary.copyToRight, other.copyToRight );
  Inc( summary.copyToLeft, other.copyToLeft );
  Inc( summary.deleteLeft, other.deleteLeft );
  Inc( summary.deleteRight, other.deleteRight );
  Inc( summary.conflicts, other.conflicts );
  Inc( summary.unreadable, other.unreadable );
  Inc( summary.equal, other.equal );
  Inc( summary.undecided, other.undecided );
end;

{ TSyncDirsView }

constructor TSyncDirsView.Create( const tree: TTwoLevelTree; const rows: TFlatDirFileList );
begin
  _tree:= tree;
  _rows:= rows;
  _opened:= TFPList.Create;
  _closed:= TFPList.Create;
  _showFiles:= True;
  _actionsIncludeSubfolders:= True;
end;

destructor TSyncDirsView.Destroy;
begin
  _opened.Free;
  _closed.Free;
  inherited Destroy;
end;

procedure TSyncDirsView.build;
begin
  collectRows;
  collectSubtrees;
  emitRows;
end;

procedure TSyncDirsView.forgetManualFolds;
begin
  _opened.Clear;
  _closed.Clear;
end;

// Each row of the row list belongs to one folder: a folder's own row, or a
// file row in it. A folder's files are contiguous, right after its own row.
procedure TSyncDirsView.collectRows;
var
  i, d: Integer;
  rec: TSyncRec;
begin
  SetLength( _dirs, _tree.Count );
  for d:= 0 to High(_dirs) do begin
    _dirs[d]:= Default( TDirInfo );
    _dirs[d].ownRow:= -1;
    _dirs[d].fileFirst:= -1;
    _dirs[d].fileLast:= -1;
    _dirs[d].first:= -1;
    _dirs[d].last:= -1;
  end;
  for i:= 0 to _rows.Count - 1 do begin
    rec:= _rows.fileSyncRec( i );
    if rec.isDir then begin
      d:= _tree.indexOfDir( rec.relPath );
      if d < 0 then continue;
      _dirs[d].ownRow:= i;
    end else begin
      d:= rec.parentDirIndex;
      if d < 0 then continue;
      if _dirs[d].fileFirst < 0 then _dirs[d].fileFirst:= i;
      _dirs[d].fileLast:= i;
    end;
    if _dirs[d].first < 0 then _dirs[d].first:= i;
    _dirs[d].last:= i;
    countRow( _dirs[d].summary, rec );
  end;
end;

// The tree lists a folder before its subfolders, so from the end every
// subtree is complete when it is added to its parent
procedure TSyncDirsView.collectSubtrees;
var
  d, p: Integer;
begin
  for d:= High(_dirs) downto 0 do begin
    p:= _tree.dirItem(d).dirSyncRec.parentDirIndex;
    if p < 0 then continue;
    addSummary( _dirs[p].summary, _dirs[d].summary );
    if _dirs[d].first < 0 then continue;
    if (_dirs[p].first < 0) or (_dirs[d].first < _dirs[p].first) then
      _dirs[p].first:= _dirs[d].first;
    if _dirs[d].last > _dirs[p].last then
      _dirs[p].last:= _dirs[d].last;
  end;
end;

procedure TSyncDirsView.emitRows;
var
  d, i, depth: Integer;
  foldedDepth: Integer = MaxInt;
  folder, fileRow: TSyncViewRow;
begin
  _count:= 0;
  for d:= 0 to High(_dirs) do begin
    depth:= depthOf( d );
    if depth > foldedDepth then continue;     // inside a folded folder
    foldedDepth:= MaxInt;
    if _dirs[d].first < 0 then continue;      // nothing visible beneath
    if depth > 0 then begin
      folder:= Default( TSyncViewRow );
      folder.rec:= _tree.dirItem(d).dirSyncRec;
      folder.dirIndex:= d;
      folder.depth:= depth;
      folder.rowIndex:= _dirs[d].ownRow;
      folder.rowFirst:= _dirs[d].first;
      folder.rowLast:= _dirs[d].last;
      if isFolded( d, depth ) then begin
        folder.kind:= vrFoldedFolder;
        addRow( folder );
        foldedDepth:= depth;
        continue;
      end;
      folder.kind:= vrFolder;
      addRow( folder );
    end;
    if NOT _showFiles or (_dirs[d].fileFirst < 0) then continue;
    for i:= _dirs[d].fileFirst to _dirs[d].fileLast do begin
      fileRow:= Default( TSyncViewRow );
      fileRow.kind:= vrFile;
      fileRow.rec:= _rows.fileSyncRec( i );
      fileRow.dirIndex:= d;
      fileRow.depth:= depth + 1;
      fileRow.rowIndex:= i;
      fileRow.rowFirst:= i;
      fileRow.rowLast:= i;
      addRow( fileRow );
    end;
  end;
end;

procedure TSyncDirsView.addRow( const row: TSyncViewRow );
begin
  if _count = Length(_view) then
    SetLength( _view, _count * 2 + 64 );
  _view[_count]:= row;
  Inc( _count );
end;

function TSyncDirsView.depthOf( const dirIndex: Integer ): Integer;
var
  path: String;
  c: Char;
begin
  path:= _tree.dirPath( dirIndex );
  if path = EmptyStr then
    Exit( 0 );
  Result:= 1;
  for c in path do
    if c = PathDelim then Inc( Result );
end;

function TSyncDirsView.isFolded( const dirIndex, depth: Integer ): Boolean;
var
  dirRec: TSyncDirRec;
begin
  dirRec:= _tree.dirItem(dirIndex).dirSyncRec;
  if _opened.IndexOf( dirRec ) >= 0 then
    Exit( False );
  if _closed.IndexOf( dirRec ) >= 0 then
    Exit( True );
  Result:= (_level > 0) and (depth >= _level);
end;

function TSyncDirsView.Count: Integer;
begin
  Result:= _count;
end;

function TSyncDirsView.row( const index: Integer ): TSyncViewRow;
begin
  Result:= _view[index];
end;

function TSyncDirsView.summaryOf( const index: Integer ): TSyncDirSummary;
begin
  Result:= _dirs[_view[index].dirIndex].summary;
end;

function TSyncDirsView.rootSummary: TSyncDirSummary;
begin
  if Length(_dirs) = 0 then
    Result:= Default( TSyncDirSummary )
  else
    Result:= _dirs[0].summary;
end;

procedure TSyncDirsView.toggle( const index: Integer );
var
  dirRec: TSyncRec;
begin
  if _view[index].kind = vrFile then
    Exit;
  dirRec:= _view[index].rec;
  if _view[index].kind = vrFoldedFolder then begin
    _closed.Remove( dirRec );
    _opened.Add( dirRec );
  end else begin
    _opened.Remove( dirRec );
    _closed.Add( dirRec );
  end;
  emitRows;
end;

procedure TSyncDirsView.rowListIndexes( const viewIndexes: TIntegerList; const target: TIntegerList );
var
  seen: array of Boolean;

  procedure take( const first, last: Integer );
  var
    i: Integer;
  begin
    if first < 0 then Exit;
    for i:= first to last do
      if NOT seen[i] then begin
        seen[i]:= True;
        target.Add( i );
      end;
  end;

var
  v: Integer;
  r: TSyncViewRow;
begin
  SetLength( seen, _rows.Count );
  for v in viewIndexes do begin
    r:= _view[v];
    case r.kind of
      vrFile:
        take( r.rowIndex, r.rowIndex );
      vrFoldedFolder:
        take( r.rowFirst, r.rowLast );
      vrFolder:
        if _actionsIncludeSubfolders then
          take( r.rowFirst, r.rowLast )
        else
          take( r.rowIndex, r.rowIndex );
    end;
  end;
end;

function TSyncDirsView.lastRowUnder( const index: Integer ): Integer;
var
  folder: TSyncViewRow;
begin
  Result:= index;
  folder:= _view[index];
  if folder.kind = vrFile then
    Exit;
  while (Result + 1 < _count) and
        (_view[Result + 1].rowFirst >= folder.rowFirst) and
        (_view[Result + 1].rowLast <= folder.rowLast) do
    Inc( Result );
end;

end.
