unit uSyncDirsTreeLines;

{
  The tree lines and [+]/[-] boxes of the Synchronize directories dialog's
  folder view, drawn in the left name column. A folder's box sits where its
  row starts; the line its children hang from runs down from the middle of
  the box, and each child joins it with a short horizontal line.
}

{$mode ObjFPC}{$H+}{$modeswitch advancedrecords}

interface

uses
  Graphics, uSyncDirsView;

const
  FOLD_BOX_SIZE = 9;

type

  { TSyncTreeLines }

  TSyncTreeLines = record
    canvas: TCanvas;
    left: Integer;     // where the rows of depth 1 start
    step: Integer;     // the indentation of each depth
    // Where a row of this depth starts: its box, or its file name
    function rowLeft( const depth: Integer ): Integer;
    procedure drawBox( const viewRow: TSyncViewRow; const top, bottom: Integer );
    // joinAt: where the row's own horizontal line ends; hasChildren: an
    // open folder with rows beneath, so its line starts in this row
    procedure drawLines( const viewRow: TSyncViewRow; const top, bottom, joinAt: Integer;
                         const hasChildren: Boolean );
  end;

implementation

function TSyncTreeLines.rowLeft( const depth: Integer ): Integer;
begin
  Result:= left + (depth - 1) * step;
end;

procedure TSyncTreeLines.drawBox( const viewRow: TSyncViewRow; const top, bottom: Integer );
var
  boxLeft, boxTop, middleX, middleY: Integer;
begin
  boxLeft:= rowLeft( viewRow.depth );
  boxTop:= (top + bottom - FOLD_BOX_SIZE) div 2;
  middleX:= boxLeft + FOLD_BOX_SIZE div 2;
  middleY:= boxTop + FOLD_BOX_SIZE div 2;
  canvas.Pen.Color:= clBtnShadow;
  canvas.Brush.Color:= clWindow;
  canvas.Rectangle( boxLeft, boxTop, boxLeft + FOLD_BOX_SIZE, boxTop + FOLD_BOX_SIZE );
  canvas.Pen.Color:= clWindowText;
  canvas.Line( boxLeft + 2, middleY, boxLeft + FOLD_BOX_SIZE - 2, middleY );
  if viewRow.kind = vrFoldedFolder then
    canvas.Line( middleX, boxTop + 2, middleX, boxTop + FOLD_BOX_SIZE - 2 );
end;

// The line for the children of a folder at depth k runs down the middle
// of that folder's box. A row crosses its ancestors' lines that go on
// below it, and joins its parent's line; that one stops at the row when it
// is the last child.
procedure TSyncTreeLines.drawLines( const viewRow: TSyncViewRow; const top, bottom, joinAt: Integer;
  const hasChildren: Boolean );

  function lineX( const depth: Integer ): Integer;
  begin
    Result:= rowLeft( depth ) + FOLD_BOX_SIZE div 2;
  end;

  function goesOn( const depth: Integer ): Boolean;
  begin
    Result:= (depth < 64) and ((viewRow.lines and (QWord(1) shl depth)) <> 0);
  end;

var
  k, middleY, parentX: Integer;
begin
  middleY:= (top + bottom) div 2;
  canvas.Pen.Color:= clBtnShadow;
  for k:= 2 to viewRow.depth - 1 do
    if goesOn( k ) then
      canvas.Line( lineX( k - 1 ), top, lineX( k - 1 ), bottom );
  if viewRow.depth >= 2 then begin
    parentX:= lineX( viewRow.depth - 1 );
    if goesOn( viewRow.depth ) then
      canvas.Line( parentX, top, parentX, bottom )
    else
      canvas.Line( parentX, top, parentX, middleY + 1 );
    canvas.Line( parentX, middleY, joinAt, middleY );
  end;
  if hasChildren then
    canvas.Line( lineX( viewRow.depth ), middleY + FOLD_BOX_SIZE div 2 + 1,
                 lineX( viewRow.depth ), bottom );
end;

end.
