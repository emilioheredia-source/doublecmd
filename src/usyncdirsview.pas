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
    procedure clearDirInfo;
    function folderOfRow( const rec: TSyncRec ): Integer;
    procedure collectSubtrees;
    procedure emitRows;
    procedure addFolderRow( const dirIndex, depth: Integer; const kind: TSyncViewRowKind );
    procedure addFileRows( const dirIndex, depth: Integer );
    procedure addRow( const row: TSyncViewRow );
    procedure rowsReachedBy( const viewRow: TSyncViewRow; out first, last: Integer );
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
    // The last grid row an action on the row at index reaches: the subtree
    // of an open folder, or just its own files when actions do not include
    // subfolders; the row itself for a file or a folded folder
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

// Counts a copy or delete action; False for any other action
function countAction( var summary: TSyncDirSummary; const action: TSyncRecState ): Boolean;
begin
  Result:= True;
  case action of
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
      Result:= False;
  end;
end;

// Where one row counts in its folder's summary. A folder's own row counts
// only when it is unreadable, a conflict or has an action (empty folders);
// a file without an action is equal or left alone.
procedure countRow( var summary: TSyncDirSummary; const rec: TSyncRec );
begin
  if rec.isUnreadable then
    Inc( summary.unreadable )
  else if rec.isTypeConflict then
    Inc( summary.conflicts )
  else if countAction( summary, rec.action ) or rec.isDir then
    Exit
  else if rec.state = srsEqual then
    Inc( summary.equal )
  else
    Inc( summary.undecided );
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
  clearDirInfo;
  for i:= 0 to _rows.Count - 1 do begin
    rec:= _rows.fileSyncRec( i );
    d:= folderOfRow( rec );
    if d < 0 then continue;
    if rec.isDir then
      _dirs[d].ownRow:= i
    else begin
      if _dirs[d].fileFirst < 0 then _dirs[d].fileFirst:= i;
      _dirs[d].fileLast:= i;
    end;
    if _dirs[d].first < 0 then _dirs[d].first:= i;
    _dirs[d].last:= i;
    countRow( _dirs[d].summary, rec );
  end;
end;

procedure TSyncDirsView.clearDirInfo;
var
  d: Integer;
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
end;

// The tree index of the folder a row belongs to: the folder itself for a
// folder's own row, the parent for a file
function TSyncDirsView.folderOfRow( const rec: TSyncRec ): Integer;
begin
  if rec.isDir then
    Result:= _tree.indexOfDir( rec.relPath )
  else
    Result:= rec.parentDirIndex;
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

// The grid rows, in tree order. The tree lists a folder's subtree right
// after it, so a folded folder's subtree is skipped by depth alone. The
// root has no row of its own: its files come first.
procedure TSyncDirsView.emitRows;
var
  d, depth: Integer;
  foldedDepth: Integer = MaxInt;
begin
  _count:= 0;
  for d:= 0 to High(_dirs) do begin
    depth:= depthOf( d );
    if depth > foldedDepth then continue;     // inside a folded folder
    foldedDepth:= MaxInt;
    if _dirs[d].first < 0 then continue;      // nothing visible beneath
    if (depth > 0) and isFolded( d, depth ) then begin
      addFolderRow( d, depth, vrFoldedFolder );
      foldedDepth:= depth;
      continue;
    end;
    if depth > 0 then
      addFolderRow( d, depth, vrFolder );
    if _showFiles then
      addFileRows( d, depth );
  end;
end;

procedure TSyncDirsView.addFolderRow( const dirIndex, depth: Integer;
  const kind: TSyncViewRowKind );
var
  folder: TSyncViewRow;
begin
  folder:= Default( TSyncViewRow );
  folder.kind:= kind;
  folder.rec:= _tree.dirItem(dirIndex).dirSyncRec;
  folder.dirIndex:= dirIndex;
  folder.depth:= depth;
  folder.rowIndex:= _dirs[dirIndex].ownRow;
  folder.rowFirst:= _dirs[dirIndex].first;
  folder.rowLast:= _dirs[dirIndex].last;
  addRow( folder );
end;

// A folder's own files, one step deeper than the folder
procedure TSyncDirsView.addFileRows( const dirIndex, depth: Integer );
var
  i: Integer;
  fileRow: TSyncViewRow;
begin
  if _dirs[dirIndex].fileFirst < 0 then
    Exit;
  for i:= _dirs[dirIndex].fileFirst to _dirs[dirIndex].fileLast do begin
    fileRow:= Default( TSyncViewRow );
    fileRow.kind:= vrFile;
    fileRow.rec:= _rows.fileSyncRec( i );
    fileRow.dirIndex:= dirIndex;
    fileRow.depth:= depth + 1;
    fileRow.rowIndex:= i;
    fileRow.rowFirst:= i;
    fileRow.rowLast:= i;
    addRow( fileRow );
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

// Overlapping selections (a folder and rows inside it) give each row list
// index once
procedure TSyncDirsView.rowListIndexes( const viewIndexes: TIntegerList; const target: TIntegerList );
var
  seen: array of Boolean;
  v, i, first, last: Integer;
begin
  SetLength( seen, _rows.Count );
  for v in viewIndexes do begin
    rowsReachedBy( _view[v], first, last );
    if first < 0 then continue;
    for i:= first to last do
      if NOT seen[i] then begin
        seen[i]:= True;
        target.Add( i );
      end;
  end;
end;

// The run of row list indexes an action on a grid row applies to: a
// folded folder always stands for its subtree, an open one only with
// "Actions include subfolders"; first < 0 when the row has none (a folder
// whose own record is not in the row list)
procedure TSyncDirsView.rowsReachedBy( const viewRow: TSyncViewRow; out first, last: Integer );
var
  wholeSubtree: Boolean;
begin
  wholeSubtree:= (viewRow.kind = vrFoldedFolder) or
                 ((viewRow.kind = vrFolder) and _actionsIncludeSubfolders);
  if wholeSubtree then begin
    first:= viewRow.rowFirst;
    last:= viewRow.rowLast;
  end else begin
    first:= viewRow.rowIndex;
    last:= viewRow.rowIndex;
  end;
end;

function TSyncDirsView.lastRowUnder( const index: Integer ): Integer;
var
  folder: TSyncViewRow;
begin
  Result:= index;
  folder:= _view[index];
  if folder.kind <> vrFolder then
    Exit;
  if _actionsIncludeSubfolders then begin
    while (Result + 1 < _count) and
          (_view[Result + 1].rowFirst >= folder.rowFirst) and
          (_view[Result + 1].rowLast <= folder.rowLast) do
      Inc( Result );
  end else begin
    while (Result + 1 < _count) and
          (_view[Result + 1].kind = vrFile) and
          (_view[Result + 1].dirIndex = folder.dirIndex) do
      Inc( Result );
  end;
end;

end.
