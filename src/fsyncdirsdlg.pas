{
   Double Commander
   -------------------------------------------------------------------------
   Directories synchronization utility (specially for DC)

   Copyright (C) 2013 Anton Panferov (ast.a_s@mail.ru)
   Copyright (C) 2014-2026 Alexander Koblov (alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program. If not, see <http://www.gnu.org/licenses/>.
}

unit fSyncDirsDlg;

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, IntegerList, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Buttons, ComCtrls, Grids, Menus, ActnList, EditBtn,
  DCOSUtils,
  uFileView, uFileSource, uFileSourceCopyOperation, uFile, uFileSourceOperation,
  uFileSourceOperationMessageBoxesUI, uFormCommands, uHotkeyManager, uClassesEx,
  uFileSourceOperationOptions, uFileSourceDeleteOperation, KASProgressBar,
  uMasks, uSearchTemplate, uFileSystemUtil, fSyncDirsPerformDlg,
  uSyncDirsModel, uSyncDirsService, uSyncDirsView;

const
  HotkeysCategory = 'Synchronize Directories';

type

  TOnGetColumnPreferedWidth = procedure (const Sender: TObject; const aCol: Integer; var preferedWidth: Integer) of object;
  TOnGetCellPreferedWidth = procedure (const Sender: TObject; const aCol: Integer; const aRow: Integer; var preferedWidth: Integer) of object;

  { TDrawGrid }

  TDrawGrid = class(Grids.TDrawGrid)
  private
    OnGetColumnPreferedWidth: TOnGetColumnPreferedWidth;
    OnGetCellPreferedWidth: TOnGetCellPreferedWidth;
    function calcPreferedWidth(const aCol: Integer): Integer;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure AutoAdjustColumn(aCol: Integer); override;
  end;

  { TSyncDirsDlgState }

  TSyncDirsDlgState = (
    sddsWaiting,

    // "Compare" button
    // running in Main Thread
    // update statistics of FFilteredCountRec in Status Bar
    // need to call Application.ProcessMessages()
    sddsScanning,

    // Compare with "by Content" checkbox
    // running in Background Thread, but in Main Thread Block other operations
    // except browsing the Grid, it is not possible to perform other operations
    // at the same time.
    // update statistics of FFilteredCountRec in Status Bar
    // update statistics of FileSize in Progress Bar
    // NO need to call Application.ProcessMessages()
    sddsCheckingContent,

    // "Synchronize" button
    // running in Main Thread
    // update statistics of FOperation in Progress Bar (FileSize and FileCount)
    // need to call Application.ProcessMessages()
    sddsSynchronizing,

    // "Delete left / Delete right / Delete Both" in Popup Context Menu
    // running in Main Thread
    // update statistics of FOperation in Progress Bar (FileCount only)
    // need to call Application.ProcessMessages()
    sddsDeletingFiles,

    // "Copy file properties" in Popup Context Menu
    // running in Main Thread
    // update statistics of FileCount in Progress Bar (FileCount only)
    // need to call Application.ProcessMessages()
    sddsCopyingProperties
  );

  { TSyncDirsDlgStateHelper }

  TSyncDirsDlgStateHelper = class
  private
    _state: TSyncDirsDlgState;
    _running: Boolean;

    constructor Create;
    procedure enter(const state: TSyncDirsDlgState); inline;
    procedure stop; inline;
    procedure reset; inline;

    function isInState(const state: TSyncDirsDlgState): Boolean; inline;
    function isRunningInState(const state: TSyncDirsDlgState): Boolean; inline;
    function isRunning: Boolean; inline;
  end;

  { TSyncDirsDlgProgressHelper }

  TSyncDirsDlgProgressHelper = class
  private
    isSize: Boolean;

    panelControl: TPanel;
    labelControl: TLabel;
    barControl: TKASProgressBar;

    caption: String;
    predefinedCaption: String;
    total: Int64;
    done: Int64;

    constructor Create(const aIsSize: Boolean; const aPanelControl: TPanel; const aLabelControl: TLabel; const aBarControl: TKASProgressBar);

    procedure open(const aCaption: String; const aTotal: Int64);
    procedure close;
    procedure update(const aDone: Int64);
    procedure updateBarControl;
  end;

  { TfrmSyncDirsDlg }

  TfrmSyncDirsDlg = class(
    TForm,
    IFormCommands,
    ISyncDirsFileProcessorWithUI,
    ISyncDirsCheckContentThreadCallback,
    ISyncDirsTreeBuilderCallback,
    ISyncDirsCommonCallback )

    actDeleteLeft: TAction;
    actDeleteRight: TAction;
    actDeleteBoth: TAction;
    actCopyPropertiesLeftToRight: TAction;
    actCopyPropertiesRightToLeft: TAction;
    actSelectDeleteLeft: TAction;
    actSelectDeleteRight: TAction;
    actSelectDeleteBoth: TAction;
    actSelectCopyReverse: TAction;
    actSelectClear: TAction;
    actSelectCopyLeftToRight: TAction;
    actSelectCopyRightToLeft: TAction;
    actSelectKeepLink: TAction;
    actSelectCopyDefault: TAction;
    ActionList: TActionList;
    btnAbort: TBitBtn;
    btnCompare: TButton;
    btnSynchronize: TButton;
    btnClose: TButton;
    chkEmptyDir: TCheckBox;
    chkAsymmetric: TCheckBox;
    chkSubDirs: TCheckBox;
    chkByContent: TCheckBox;
    chkIgnoreDate: TCheckBox;
    chkOnlySelected: TCheckBox;
    cbExtFilter: TComboBox;
    cbExcludeDirs: TComboBox;
    cbExcludeFiles: TComboBox;
    lblExcludeDirs: TLabel;
    lblExcludeFiles: TLabel;
    pnlExclude: TPanel;
    pnlView: TPanel;
    lblViewLevel: TLabel;
    cbViewLevel: TComboBox;
    btnExpandAll: TButton;
    btnCollapseAll: TButton;
    chkViewFiles: TCheckBox;
    chkViewIndent: TCheckBox;
    chkActionsSubfolders: TCheckBox;
    edPath1: TDirectoryEdit;
    edPath2: TDirectoryEdit;
    HeaderDG: TDrawGrid;
    lblFileSizeProgress: TLabel;
    lblFileCountProgress: TLabel;
    MainDrawGrid: TDrawGrid;
    GroupBox1: TGroupBox;
    ImageList1: TImageList;
    Label1: TLabel;
    LeftPanel1: TPanel;
    LeftPanel2: TPanel;
    miCopyPropertiesRightToLeft: TMenuItem;
    miCopyPropertiesLeftToRight: TMenuItem;
    miSeparator4: TMenuItem;
    miDeleteBoth: TMenuItem;
    miDeleteRight: TMenuItem;
    miDeleteLeft: TMenuItem;
    miSeparator3: TMenuItem;
    miSelectDeleteLeft: TMenuItem;
    miSelectDeleteRight: TMenuItem;
    miSelectDeleteBoth: TMenuItem;
    miSeparator2: TMenuItem;
    miSelectCopyReverse: TMenuItem;
    miSeparator1: TMenuItem;
    miSelectCopyLeftToRight: TMenuItem;
    miSelectCopyRightToLeft: TMenuItem;
    miSelectKeepLink: TMenuItem;
    miSelectCopyDefault: TMenuItem;
    miSelectClear: TMenuItem;
    MenuItemCompare: TMenuItem;
    MenuItemViewRight: TMenuItem;
    MenuItemViewLeft: TMenuItem;
    pnlFilter: TPanel;
    pnlProgress: TPanel;
    pnlFileSizeProgress: TPanel;
    pnlFileCountProgress: TPanel;
    pmGridMenu: TPopupMenu;
    pbFileSizeProgress: TKASProgressBar;
    pbFileCountProgress: TKASProgressBar;
    sbCopyRight: TSpeedButton;
    sbEqual: TSpeedButton;
    sbNotEqual: TSpeedButton;
    sbUnknown: TSpeedButton;
    sbCopyLeft: TSpeedButton;
    sbDuplicates: TSpeedButton;
    sbSingles: TSpeedButton;
    btnSearchTemplate: TSpeedButton;
    StatusBar1: TStatusBar;
    Timer: TTimer;
    TopPanel: TPanel;
    procedure actExecute(Sender: TObject);
    procedure btnAbortClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure btnSearchTemplateClick(Sender: TObject);
    procedure cbExtFilterChange(Sender: TObject);
    procedure cbViewLevelChange(Sender: TObject);
    procedure btnExpandAllClick(Sender: TObject);
    procedure btnCollapseAllClick(Sender: TObject);
    procedure chkViewFilesChange(Sender: TObject);
    procedure chkViewIndentChange(Sender: TObject);
    procedure chkActionsSubfoldersChange(Sender: TObject);
    procedure btnCompareClick(Sender: TObject);
    procedure btnSynchronizeClick(Sender: TObject);
    procedure edPath1AcceptDirectory(Sender: TObject; var Value: String);
    procedure RestoreProperties(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure MainDrawGridGetCellPreferedWidth(const Sender: TObject;
      const aCol: Integer; const aRow: Integer; var preferedWidth: Integer);
    procedure MainDrawGridDblClick(Sender: TObject);
    procedure MainDrawGridDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure MainDrawGridKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure MainDrawGridMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HeaderDGHeaderClick(Sender: TObject; IsColumn: Boolean;
      Index: Integer);
    procedure HeaderDGHeaderSizing(sender: TObject; const IsColumn: boolean;
      const aIndex, aSize: Integer);
    procedure HeaderDGHeaderSized(Sender: TObject; IsColumn: Boolean;
      Index: Integer);
    procedure HeaderDGGetColumnPreferedWidth(const Sender: TObject;
      const aCol: Integer; var preferedWidth: Integer);
    procedure FilterSpeedButtonClick(Sender: TObject);
    procedure MenuItemViewClick(Sender: TObject);
    procedure pmGridMenuPopup(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
  private
    FCommands: TFormCommands;
    FIniPropStorage: TIniPropStorageEx;
  private
    { private declarations }
    FState: TSyncDirsDlgStateHelper;
    // What the list shows: nothing yet, a whole compare, or a cancelled one
    FCompareState: (csNotCompared, csCompared, csCancelled);
    // Compare progress: shown at most every 50 ms, never going back
    FLastMessagesTime: QWord;
    FScanShownPercent: Integer;
    FSortService: TSyncDirsSortService;
    FFullTree: TTwoLevelTree;
    FFilteredList: TFlatDirFileList;
    FSortIndex: Integer;
    FSortDesc: Boolean;
    FCompareOption: TSyncDirsCompareOption;
    FMaskList: TMaskList;
    FTemplate: TSearchTemplate;
    FSelectedFiles: TDoubleFiles;
    FFileSources: TDoubleFileSources;
    FCmpFileSources: TDoubleFileSources;
    FCmpFilePaths: TDoublePaths;
    FAddresses: TDoublePaths;
    hCols: array [0..6] of record Left, Width: Integer end;
    FFilteredCountRec: TSyncDirsFlatCountRec;
    // What the grid shows: the row list seen by folder (see uSyncDirsView)
    FView: TSyncDirsView;
    FOperation: TFileSourceOperation;
    FileExistsOption: TFileSourceOperationOptionFileExists;
    SymLinkOption: TFileSourceOperationOptionSymLink;
    VerifyOption: Boolean;
    // Carried from one copy batch to the next, so "All"-type answers hold
    // for the whole run
    OverwriteReadOnly: Boolean;
    SkipAllErrors: Boolean;
    DirExistsOption: TFileSourceOperationOptionDirectoryExists;
    SetPropertyError: TFileSourceOperationOptionSetPropertyError;
    SkipFlags: TFileSystemOperationHelperSkipFlags;
    // The same for delete batches. Whether deletions go to the trash is
    // preset from the global setting and chosen per run.
    FDeleteSkipErrors: Boolean;
    FDeleteReadOnlyOption: TFileSourceOperationOptionGeneral;
    FDeleteDirectlyOption: TFileSourceOperationOptionGeneral;
    FDeleteToTrash: Boolean;
    FCopyStatistics: TFileSourceCopyOperationStatistics;
    FDeleteStatistics: TFileSourceDeleteOperationStatistics;
    FFileSourceOperationMessageBoxesUI: TFileSourceOperationMessageBoxesUI;

    FFileSizeProgressHelper: TSyncDirsDlgProgressHelper;
    FFileCountProgressHelper: TSyncDirsDlgProgressHelper;

    function createCompareOption: TSyncDirsCompareOption;
    function createFilterFlags: TFilterFlags;
    function createSelectionIndexes: TIntegerList;

    procedure toggleSelectionAction; inline;
    procedure setSelectionAction(const newAction: TSyncRecState);

    function stopOperation: Boolean;
    procedure doCopyProperties(const targetSide: TDoubleSide);

    function getDisplayText(const aCol: Integer; const aRow: Integer): String;

    procedure Compare;
    procedure FillFoundItemsDG;
    procedure InitVisibleItems;
    procedure RecalcHeaderCols;
    procedure ScanDirs;
    procedure SetSortIndex(AValue: Integer);
    procedure UpdateStatusBar;
    procedure EnableControls(AEnabled: Boolean);
    procedure DeleteSelectedFiles(ALeft, ARight: Boolean);
    function confirmSkippedItems(const syncCount: TSyncDirsSyncCount): Boolean;
    procedure UpdateExcludeFieldsState;
    function createExclusionTemplate: TSearchTemplate;
    procedure takeRunOptions(const dialog: TfrmSyncDirsPerformDlg);
    procedure applyViewSettings;
    procedure setViewLevel(const level: Integer);
    procedure foldAllAt(const level: Integer);
    procedure refreshView;
    procedure refoldView;
    procedure toggleFolderRow(const viewIndex: Integer);
    function clickedFoldMarker(const viewIndex, X: Integer): Boolean;
    function rowIndentation(const depth: Integer): Integer;
    function folderRowName(const dirIndex: Integer): String;
    procedure drawFolderRow(const viewRow: TSyncViewRow; const summary: TSyncDirSummary;
                            const aRect: TRect; const aState: TGridDrawState);
    procedure drawFileRow(const viewRow: TSyncViewRow; const aRect: TRect);
    procedure drawFileSide(const aFile: TFile; const fileName: String;
                           const nameCol, sizeCol, dateCol, indent: Integer; const aRect: TRect);
    procedure drawActionIcon(const rowAction: TSyncRecState; const aRect: TRect);
    function folderRowAction(const viewIndex: Integer): TSyncRecState;
    function toggleCursorFolder(const kind: TSyncViewRowKind): Boolean;
    procedure ApplyCopyOptions(const operation: TFileSourceOperation);
    procedure RememberCopyOptions(const operation: TFileSourceOperation);
    procedure ResetDeleteOptions;
    procedure ApplyDeleteOptions(const operation: TFileSourceOperation);
    procedure RememberDeleteOptions(const operation: TFileSourceOperation);
    function trashAvailableOn(const side: TDoubleSide): Boolean;

  private
    function fileProcessorWithUICopyFiles(
      const sourceFS: IFileSource;
      const targetFS: IFileSource;
      var files: TFiles;
      const targetPath: String): Boolean;
    function fileProcessorWithUIDeleteFiles(
      const FileSource: IFileSource;
      var Files: TFiles): Boolean;
    function fileProcessorWithUICopyProperties(
      const targetFS: IFileSource;
      const sourceFile: TFile;
      const targetFile: TFile;
      const attrs: TCopyAttributesOptions ): Boolean;

  private
    FCheckContentThread: TSyncDirsCheckContentThread;
    FCheckContentThreadTimerCount: Integer;
  private
    procedure onCheckContentThreadStart;
    procedure onCheckContentThreadFinish;
    procedure onCheckContentThreadReapplyFilter;
    procedure onCheckContentThreadCountUpdated( const totalInc: Integer; const equalInc: Integer; const notEqInc: Integer );

    procedure checkContentThreadStart;
    procedure checkContentThreadStop;
    procedure checkContentThreadUpdateStat(const doneBytes: Int64; const totalBytes: Int64);

  private
    function treeBuilderMaskFilt( const f: TFile ): Boolean;
    function treeBuilderUnreadable( const side: TDoubleSide; const path: String ): TSyncDirsUnreadableAnswer;
    procedure onTreeBuilderUpdateProgress( const percent: Integer );

  private
    function commonCheckRunning(const processMessages: Boolean): Boolean;
    function SyncSearchProgress(SourceName, TargetName: PAnsiChar; PercentDone: Integer): Integer;

  private
    property leftFS: IFileSource read FFileSources[dsLeft] write FFileSources[dsLeft];
    property rightFS: IFileSource read FFileSources[dsRight] write FFileSources[dsRight];
    property leftAddress: String read FAddresses[dsLeft] write FAddresses[dsLeft];
    property rightAddress: String read FAddresses[dsRight] write FAddresses[dsRight];

    property SortIndex: Integer read FSortIndex write SetSortIndex;
    property Commands: TFormCommands read FCommands implements IFormCommands;
  protected
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
                                 const AXProportion, AYProportion: Double); override;
  public
    { public declarations }
    constructor Create(AOwner: TComponent;
      FileView1, FileView2: TFileView); reintroduce;
    destructor Destroy; override;
  public
    procedure CopyToClipboard;
  published
    procedure cm_SelectClear(const {%H-}Params:array of string);
    procedure cm_SelectDeleteLeft(const {%H-}Params:array of string);
    procedure cm_SelectDeleteRight(const {%H-}Params:array of string);
    procedure cm_SelectDeleteBoth(const {%H-}Params:array of string);
    procedure cm_SelectCopyDefault(const {%H-}Params:array of string);
    procedure cm_SelectCopyReverse(const {%H-}Params:array of string);
    procedure cm_SelectCopyLeftToRight(const {%H-}Params:array of string);
    procedure cm_SelectCopyRightToLeft(const {%H-}Params:array of string);
    procedure cm_SelectKeepLink(const {%H-}Params:array of string);

    procedure cm_DeleteLeft(const {%H-}Params:array of string);
    procedure cm_DeleteRight(const {%H-}Params:array of string);
    procedure cm_DeleteBoth(const {%H-}Params:array of string);

    procedure cm_CopyPropertiesLeftToRight(const {%H-}Params:array of string);
    procedure cm_CopyPropertiesRightToLeft(const {%H-}Params:array of string);
  end;

resourcestring
  rsComparingPercent = 'Comparing... %d%% (ESC to cancel)';
  rsLeftToRightCopy = 'Left to Right: Copy %d files, total size: %s (%s)';
  rsRightToLeftCopy = 'Right to Left: Copy %d files, total size: %s (%s)';
  rsDeleteLeft = 'Left: Delete %d file(s)';
  rsDeleteRight = 'Right: Delete %d file(s)';
  rsFilesFound = 'Files found: %d  (Identical: %d, Different: %d, '
    + 'Unique left: %d, Unique right: %d)';
  rsSyncCannotRead = 'Cannot read folder "%s".'
    + ' Skipping it leaves the folder untouched on both sides.';
  rsSyncUnreadable = '<could not be read>';
  rsSyncFoldersUnreadable = '%d folder(s) could not be read';
  rsSyncNotCompared = 'Not compared yet: press Compare';
  rsSyncCompareCancelled = 'Compare cancelled, the list is incomplete.';
  rsSyncCompareCancelledWarning = 'The compare was cancelled, so the list covers'
    + ' only part of the tree. Only what it shows will be synchronized; nothing'
    + ' that was not listed is copied or deleted. Continue?';
  rsSyncUnreadableWarning = '%d folder(s) could not be read. They are left'
    + ' untouched on both sides and will not be synchronized. Continue?';
  rsSyncTypeConflicts = '%d item(s) differ in type (red)';
  rsSyncTypeConflictWarning = '%d item(s) are a folder on one side and a file or'
    + ' link on the other (shown in red) and have no action set. They are left'
    + ' untouched on both sides and will not be synchronized. Continue?';
  rsSyncTypeConflictReplace = '%d item(s) shown in red will replace an item of a'
    + ' different type on the other side. What is there now is deleted first'
    + ' - for a folder, everything in it - and the item is then copied over'
    + ' whole. Continue?';

procedure ShowSyncDirsDlg(FileView1, FileView2: TFileView);

implementation

uses
  fMain, uDebug, fDiffer, fSyncDirsSelectPropertiesDlg, fSelectFileProperties,
  uGlobs, LCLType, LazUTF8, LazFileUtils,
  uFileSystemFileSource, DCDateTimeUtils,
  uDCUtils, uFileSourceOperationTypes, uShowForm, uAdministrator,
  uOSUtils, uLng, Math, uClipboard, fMaskInputDlg,
  LCLVersion, uTypes, uFileSystemCopyOperation, uFileSystemDeleteOperation, uFindFiles,
  uWfxPluginCopyInOperation,
  uFileSourceManager, uFileSourceProperty, uShowMsg,
  fDeleteDlg, uTrash, uOperationsManager, uOSForms,
  uWfxPluginFileSource, WfxPlugin
  {$IF DEFINED(LCLGTK2)}
  , uGtk2ListCombo
  {$ENDIF}
  ;

// With "Indent" on, rows are indented by their depth in the tree and a
// folder row shows its own name: its files and subfolders sit one step to
// the right of it. Off, as upstream drew it: no indentation and folder rows
// with their path from the root. File rows show the file name either way.
function TfrmSyncDirsDlg.rowIndentation(const depth: Integer): Integer;
const
  STEP = 16;
begin
  if NOT chkViewIndent.Checked then
    Exit(0);
  Result := Max(0, depth - 1) * STEP;
end;

function TfrmSyncDirsDlg.folderRowName(const dirIndex: Integer): String;
begin
  Result := FFullTree.dirPath(dirIndex);
  if chkViewIndent.Checked then
    Result := ExtractFileName(Result);
  Result := Result + PathDelim;
end;

procedure TfrmSyncDirsDlg.chkViewIndentChange(Sender: TObject);
begin
  MainDrawGrid.Invalidate;
end;


{$R *.lfm}

const
  GRID_COLUMN_FMT = 'HeaderDG_Column%d_Width';

const
  LEFT_FILE_INDENTATION = 8;

procedure ShowSyncDirsDlg(FileView1, FileView2: TFileView);
var
  dlg: TfrmSyncDirsDlg;

  function isSupported: Boolean;
  var
    leftFS: IFileSource;
    rightFS: IFileSource;
  begin
    Result:= False;
    leftFS:= FileView1.FileSource;
    rightFS:= FileView2.FileSource;
    if NOT (fspSynchronizable in leftFS.GetProperties) then
      Exit;
    if NOT (fspSynchronizable in rightFS.GetProperties) then
      Exit;
    if NOT TSyncDirsUtil.supportsSyncDirs(leftFS,rightFS) then
      Exit;
    Result:= True;
  end;

begin
  if not Assigned(FileView1) then
    raise Exception.Create('ShowSyncDirsDlg: FileView1=nil');
  if not Assigned(FileView2) then
    raise Exception.Create('ShowSyncDirsDlg: FileView2=nil');
  if NOT isSupported then begin
    msgWarning(rsMsgErrNotSupported);
    Exit;
  end;

  dlg:= TfrmSyncDirsDlg.Create(Application, FileView1, FileView2);
  // On the same monitor as the main window, not the middle of the desktop
  with GetFrmMainMonitor do
    dlg.SetBounds(Left + (Width - dlg.Width) div 2, Top + (Height - dlg.Height) div 2,
                  dlg.Width, dlg.Height);
  dlg.Show;
end;

{ TDrawGrid }

function TDrawGrid.calcPreferedWidth(const aCol: Integer): Integer;
var
  aRow: Integer;
  currentWidth: Integer;
begin
  Result:= 0;
  for aRow:= GCache.VisibleGrid.Top to GCache.VisibleGrid.Bottom do begin
    OnGetCellPreferedWidth(self, aCol, aRow, currentWidth);
    if currentWidth > Result then
      Result:= currentWidth;
  end;
end;

procedure TDrawGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  C, R: Integer;
begin
  if Button <> mbRight then
    inherited MouseDown(Button, Shift, X, Y)
  else begin
    MouseToCell(X, Y, {%H-}C, {%H-}R);
    if (R >= 0) and (R < RowCount) then
    begin
      if not IsCellSelected[Col, R] then begin
        self.Row:= R;
        self.ClearSelections;
      end else begin
        C:= Row;
        PInteger(@Row)^:= R;
        InvalidateRow(C);
        InvalidateRow(R);
      end;
    end;
  end;
end;

procedure TDrawGrid.AutoAdjustColumn(aCol: Integer);
var
  preferedWidth: Integer;
  column: TGridColumn;
begin
  if NOT Assigned(OnGetColumnPreferedWidth) then
    Exit;

  OnGetColumnPreferedWidth(self, aCol, preferedWidth);
  column:= self.Columns[aCol];
  if preferedWidth < column.MinSize then
    preferedWidth:= column.MinSize;
  column.Width:= preferedWidth;
end;

{ TSyncDirsDlgStateHelper }

constructor TSyncDirsDlgStateHelper.Create;
begin
  self.reset;
end;

procedure TSyncDirsDlgStateHelper.enter(const state: TSyncDirsDlgState);
begin
  _state:= state;
  _running:= True;
end;

procedure TSyncDirsDlgStateHelper.stop;
begin
  _running:= False;
end;

procedure TSyncDirsDlgStateHelper.reset;
begin
  _state:= sddsWaiting;
  _running:= True;
end;

function TSyncDirsDlgStateHelper.isInState(const state: TSyncDirsDlgState): Boolean;
begin
  Result:= (_state=state);
end;

function TSyncDirsDlgStateHelper.isRunningInState(const state: TSyncDirsDlgState): Boolean;
begin
  Result:= _running AND self.isInState(state);
end;

function TSyncDirsDlgStateHelper.isRunning: Boolean;
begin
  Result:= _running AND NOT self.isInState(sddsWaiting);
end;

{ TSyncDirsDlgProgressHelper }

constructor TSyncDirsDlgProgressHelper.Create(
  const aIsSize: Boolean;
  const aPanelControl: TPanel;
  const aLabelControl: TLabel;
  const aBarControl: TKASProgressBar);
begin
  self.isSize:= aIsSize;
  self.panelControl:= aPanelControl;
  self.labelControl:= aLabelControl;
  self.barControl:= aBarControl;
end;

procedure TSyncDirsDlgProgressHelper.open(const aCaption: String; const aTotal: Int64);
begin
  self.labelControl.Caption:= aCaption;
  self.caption:= aCaption;
  self.predefinedCaption:= EmptyStr;
  self.total:= aTotal;
  self.done:= 0;
  self.updateBarControl;
  self.panelControl.Show;
end;

procedure TSyncDirsDlgProgressHelper.close;
begin
  self.caption:= EmptyStr;
  self.panelControl.Hide;
end;

procedure TSyncDirsDlgProgressHelper.update(const aDone: Int64);
begin
  self.done:= aDone;
  self.updateBarControl;
end;

procedure TSyncDirsDlgProgressHelper.updateBarControl;
var
  barText : String;
  labelText : String;
begin
  if self.caption = EmptyStr then
    Exit;

  if self.isSize then begin
    {
      not all FileSources can provide precise statistical information,
      nor can they accurately calculate the generated size, for example, MultiArchive/7z.
      so this check has been added to prevent reporting an erroneous progress exceeding 100%
    }
    if self.done > self.total then
      self.total:= self.done + 1;
    barText := cnvFormatFileSize(self.done, uoscOperation) + '/' + cnvFormatFileSize(self.total, uoscOperation);
  end else begin
    {
      1. defensively prevent exceeding 100%
      2. for "Delete all empty directories"
    }
    if self.done > self.total then
      self.total:= self.done;
    barText := IntToStrTS(self.done) + '/' + IntToStrTS(self.total);
  end;
  self.barControl.SetProgress(self.done, self.total, barText);

  {$IFDEF LCLCOCOA}
  if self.predefinedCaption <> EmptyStr then begin
    labelText := self.predefinedCaption
  end else if self.total > 0 then begin
    labelText := self.caption + ': ' + barText + ' (' + FloatToStrF((self.done / self.total) * 100, ffFixed, 0, 0) + '%)'
  end else begin
    labelText := self.caption;
  end;
  self.labelControl.Caption := labelText;
  {$ENDIF}
end;

{ TfrmSyncDirsDlg }

procedure TfrmSyncDirsDlg.actExecute(Sender: TObject);
var
  cmd: string;
begin
  cmd := (Sender as TAction).Name;
  cmd := 'cm_' + Copy(cmd, 4, Length(cmd) - 3);
  Commands.ExecuteCommand(cmd, []);
end;

procedure TfrmSyncDirsDlg.btnCloseClick(Sender: TObject);
begin
  Close
end;

procedure TfrmSyncDirsDlg.btnSearchTemplateClick(Sender: TObject);
var
  sMask: String;
  bTemplate: Boolean;
begin
  sMask:= cbExtFilter.Text;
  if ShowMaskInputDlg(rsMarkPlus, rsMaskInput, glsSyncMaskHistory, sMask) then
  begin
    bTemplate:= IsMaskSearchTemplate(sMask);
    cbExtFilter.Enabled:= not bTemplate;
    cbExtFilter.Text:= sMask;
    UpdateExcludeFieldsState;
  end;
end;

// A named search template carries its own exclusions, so the inline fields
// would be silently ignored. Grey them out rather than let them look active.
procedure TfrmSyncDirsDlg.UpdateExcludeFieldsState;
var
  bTemplate: Boolean;
begin
  bTemplate:= IsMaskSearchTemplate(cbExtFilter.Text);
  cbExcludeDirs.Enabled:= not bTemplate;
  cbExcludeFiles.Enabled:= not bTemplate;
  lblExcludeDirs.Enabled:= not bTemplate;
  lblExcludeFiles.Enabled:= not bTemplate;
end;

procedure TfrmSyncDirsDlg.cbExtFilterChange(Sender: TObject);
begin
  UpdateExcludeFieldsState;
end;

// Exclusions typed straight into the dialog, wrapped in a throwaway template
// so they run through the same FileChecks path a named template uses. The
// file mask must be '*': an empty mask matches nothing, which would reject
// every file. The real mask stays with FMaskList. Nil when both are empty.
function TfrmSyncDirsDlg.createExclusionTemplate: TSearchTemplate;
var
  SearchRec: TSearchTemplateRec;
begin
  Result:= nil;
  if (Trim(cbExcludeDirs.Text) = EmptyStr) and (Trim(cbExcludeFiles.Text) = EmptyStr) then
    Exit;
  Result:= TSearchTemplate.Create;
  SearchRec:= Result.SearchRecord;
  SearchRec.FilesMasks:= '*';
  SearchRec.ExcludeDirectories:= Trim(cbExcludeDirs.Text);
  SearchRec.ExcludeFiles:= Trim(cbExcludeFiles.Text);
  Result.SearchRecord:= SearchRec;
end;

procedure TfrmSyncDirsDlg.btnAbortClick(Sender: TObject);
begin
  self.stopOperation;
end;

procedure TfrmSyncDirsDlg.btnCompareClick(Sender: TObject);
begin
  if not IsMaskSearchTemplate(cbExtFilter.Text) then
    InsertFirstItem(Trim(cbExtFilter.Text), cbExtFilter);
  if Trim(cbExcludeDirs.Text) <> EmptyStr then
    InsertFirstItem(Trim(cbExcludeDirs.Text), cbExcludeDirs);
  if Trim(cbExcludeFiles.Text) <> EmptyStr then
    InsertFirstItem(Trim(cbExcludeFiles.Text), cbExcludeFiles);
  StatusBar1.Panels[0].Text := Format(rsComparingPercent, [0]);
  Compare;
end;

procedure TfrmSyncDirsDlg.btnSynchronizeClick(Sender: TObject);
  function getAddressPath(const side: TDoubleSide): String;
  begin
    Result:= FCmpFileSources[side].CurrentAddress + FCmpFilePaths[side];
  end;
var
  synchronizer: TSyncDirsSynchronizer;
  syncCount: TSyncDirsSyncCount;
  syncFlags: TSyncDirsSyncFlags;
  dialog: TfrmSyncDirsPerformDlg;
  fileSizeVisible: Boolean;
  fileCountVisible: Boolean;
begin
  synchronizer:= TSyncDirsSynchronizer.Create( self, self, FFilteredList, FCmpFileSources, FCmpFilePaths );
  syncCount:= synchronizer.count;
  syncFlags:= [];
  if NOT confirmSkippedItems( syncCount ) then begin
    synchronizer.Free;
    Exit;
  end;

  FCopyStatistics.DoneBytes:= 0;
  FDeleteStatistics.DoneFiles:= 0;
  FCopyStatistics.TotalBytes:= syncCount.copySize;
  FDeleteStatistics.TotalFiles:= syncCount.deleteCount;

  dialog:= TfrmSyncDirsPerformDlg.Create(Self);
  with dialog do
  try
    edLeftPath.Text := getAddressPath(dsLeft);
    edRightPath.Text := getAddressPath(dsRight);;
    if syncCount.copyToLeftCount > 0 then
    begin
      chkRightToLeft.Enabled := True;
      chkRightToLeft.Checked := True;
      edLeftPath.Enabled := True;
    end;
    if syncCount.copyToRightCount > 0 then
    begin
      chkLeftToRight.Enabled := True;
      chkLeftToRight.Checked := True;
      edRightPath.Enabled := True;
    end;
    chkDeleteLeft.Enabled := syncCount.deleteLeftCount > 0;
    chkDeleteLeft.Checked := chkDeleteLeft.Enabled;
    chkDeleteRight.Enabled := syncCount.deleteRightCount > 0;
    chkDeleteRight.Checked := chkDeleteRight.Enabled;
    chkDeleteLeft.Caption := Format(rsDeleteLeft, [syncCount.deleteLeftCount]);
    chkDeleteRight.Caption := Format(rsDeleteRight, [syncCount.deleteRightCount]);
    chkLeftToRight.Caption :=
      Format(rsLeftToRightCopy, [syncCount.copyToRightCount, cnvFormatFileSize(syncCount.copyToRightSize, fsfFloat, gFileSizeDigits), IntToStrTS(syncCount.copyToRightSize)]);
    chkRightToLeft.Caption :=
      Format(rsRightToLeftCopy, [syncCount.copyToLeftCount, cnvFormatFileSize(syncCount.copyToLeftSize, fsfFloat, gFileSizeDigits), IntToStrTS(syncCount.copyToLeftSize)]);
    chkVerify.Visible := TSyncDirsUtil.supportsVerify(FCmpFileSources);
    chkVerify.Checked := gOperationOptionVerify;
    chkOverwriteReadOnly.Checked := gSyncDirsOverwriteReadOnly;
    chkDeleteToTrash.Checked := gSyncDirsDeleteToTrash;
    // A mirror keeps the empty folders the source has and loses the ones
    // it does not; deleting all of them on a side is no part of it
    chkDeleteLeftAllEmptyDirs.Visible := NOT chkAsymmetric.Checked;
    chkDeleteRightAllEmptyDirs.Visible := NOT chkAsymmetric.Checked;

    if ShowModal = mrOk then
    begin
      FState.enter(sddsSynchronizing);
      EnableControls(False);
      takeRunOptions(dialog);

      if chkRightToLeft.Checked then
        Include( syncFlags, sfCopyToLeft );
      if chkLeftToRight.Checked then
        Include( syncFlags, sfCopyToRight );
      if chkDeleteLeft.Checked then
        Include( syncFlags, sfDeleteLeft );
      if chkDeleteRight.Checked then
        Include( syncFlags, sfDeleteRight );
      if chkDeleteLeftAllEmptyDirs.Checked then
        Include( syncFlags, sfDeleteLeftAllEmptyDirs );
      if chkDeleteRightAllEmptyDirs.Checked then
        Include( syncFlags, sfDeleteRightAllEmptyDirs );

      fileSizeVisible:= (sfCopyToLeft in syncFlags) or (sfCopyToRight in syncFlags);
      fileCountVisible:= (sfDeleteLeft in syncFlags) or (sfDeleteRight in syncFlags) or
                         (sfDeleteLeftAllEmptyDirs in syncFlags) or (sfDeleteRightAllEmptyDirs in syncFlags);

      if fileSizeVisible then
        FFileSizeProgressHelper.open(rsOperCopying, syncCount.copySize)
      else
        FFileSizeProgressHelper.close;
      if fileCountVisible then
        FFileCountProgressHelper.open(rsOperDeleting, syncCount.deleteCount)
      else
        FFileCountProgressHelper.close;

      synchronizer.sync( syncFlags );
    end;
  finally
    if FState.isInState(sddsSynchronizing) then begin
      FFileSizeProgressHelper.close;
      FFileCountProgressHelper.close;
      EnableControls(True);
      FState.reset;
      btnCompare.Click;
    end;
    synchronizer.Free;
    Free;
  end;
end;

procedure TfrmSyncDirsDlg.edPath1AcceptDirectory(Sender: TObject; var Value: String);
var
  side: TDoubleSide;
begin
  if Sender = edPath1 then
    side:= dsLeft
  else
    side:= dsRight;
  FFileSources[side] := TFileSystemFileSource.GetFileSource;
  FAddresses[side] := '';
end;

procedure TfrmSyncDirsDlg.MainDrawGridMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  if Button <> mbLeft then
    Exit;

  MainDrawGrid.MouseToCell(X, Y, c, r);
  if (r < 0) or (r >= FView.Count) then
    Exit;

  if clickedFoldMarker(r, X) then
  begin
    toggleFolderRow(r);
    Exit;
  end;

  if (x - 2 < hCols[3].Left)
  or (x - 2 > hCols[3].Left + hCols[3].Width)
  then
    Exit;

  toggleSelectionAction;
end;

// The [+]/[-] marker at the start of a folder row
function TfrmSyncDirsDlg.clickedFoldMarker(const viewIndex, X: Integer): Boolean;
const
  MARKER_WIDTH = 24;
var
  markerLeft: Integer;
begin
  if FView.row(viewIndex).kind = vrFile then
    Exit(False);
  markerLeft := hCols[0].Left + 2 + rowIndentation(FView.row(viewIndex).depth);
  Result := (X >= markerLeft) and (X < markerLeft + MARKER_WIDTH);
end;

procedure TfrmSyncDirsDlg.RestoreProperties(Sender: TObject);
var
  Index: Integer;
begin
  with HeaderDG.Columns do
  begin
    for Index := 0 to Count - 2 do
      Items[Index].Width:= StrToIntDef(FIniPropStorage.StoredValue[Format(GRID_COLUMN_FMT, [Index])], Items[Index].Width);
  end;
  RecalcHeaderCols;
end;

procedure TfrmSyncDirsDlg.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  Index: Integer;
begin
  checkContentThreadStop;
  CloseAction := caFree;
  { settings }
  gSyncDirsEmptyDirs            := chkEmptyDir.Checked;
  gSyncDirsSubdirs              := chkSubDirs.Checked;
  gSyncDirsAsymmetric           := chkAsymmetric.Checked;
  gSyncDirsIgnoreDate           := chkIgnoreDate.Checked;
  gSyncDirsShowFilterCopyRight  := sbCopyRight.Down;
  gSyncDirsShowFilterEqual      := sbEqual.Down;
  gSyncDirsShowFilterNotEqual   := sbNotEqual.Down;
  gSyncDirsShowFilterUnknown    := sbUnknown.Down;
  gSyncDirsShowFilterCopyLeft   := sbCopyLeft.Down;
  gSyncDirsShowFilterDuplicates := sbDuplicates.Down;
  gSyncDirsShowFilterSingles    := sbSingles.Down;
  if gSyncDirsFileMaskSave = True then
  begin
    if not IsMaskSearchTemplate(cbExtFilter.Text) then
      gSyncDirsFileMask         := cbExtFilter.Text;
  end;
  if chkByContent.Enabled then
    gSyncDirsByContent          := chkByContent.Checked;
  gSyncDirsExcludeDirs          := Trim(cbExcludeDirs.Text);
  gSyncDirsExcludeFiles         := Trim(cbExcludeFiles.Text);
  gSyncDirsViewLevel            := FView.level;
  gSyncDirsViewFiles            := chkViewFiles.Checked;
  gSyncDirsViewIndent           := chkViewIndent.Checked;
  gSyncDirsActionsSubfolders    := chkActionsSubfolders.Checked;
  glsSyncMaskHistory.Assign(cbExtFilter.Items);
  // Exclusion history is shared with the Find files dialog: the same folder
  // and file patterns get skipped in both places.
  glsSearchExcludeDirectories.Assign(cbExcludeDirs.Items);
  glsSearchExcludeFiles.Assign(cbExcludeFiles.Items);

  with HeaderDG.Columns do
  begin
    for Index := 0 to Count - 2 do
      FIniPropStorage.StoredValue[Format(GRID_COLUMN_FMT, [Index])]:= IntToStr(Items[Index].Width);
  end;
end;

procedure TfrmSyncDirsDlg.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  CanClose:= NOT self.stopOperation;
end;

procedure TfrmSyncDirsDlg.FormCreate(Sender: TObject);
var
  Index: Integer;
  HMSync: THMForm;
begin
  // Initialize property storage
  FIniPropStorage := InitPropStorage(Self);
  FIniPropStorage.OnRestoreProperties:= @RestoreProperties;
  for Index := 0 to HeaderDG.Columns.Count - 1 do
  begin
    FIniPropStorage.StoredValues.Add.DisplayName:= Format(GRID_COLUMN_FMT, [Index]);
  end;
  HeaderDG.OnGetColumnPreferedWidth:= @HeaderDGGetColumnPreferedWidth;

  {$IFDEF LCLCOCOA}
  pnlProgress.Color:=clBtnHighlight;
  {$ENDIF}
  MainDrawGrid.SelectedColor:= gColors.SyncDirs^.SelectedColor;
  MainDrawGrid.OnGetCellPreferedWidth:= @MainDrawGridGetCellPreferedWidth;

  FFileSizeProgressHelper:= TSyncDirsDlgProgressHelper.Create(
    True,
    pnlFileSizeProgress,
    lblFileSizeProgress,
    pbFileSizeProgress);
  FFileCountProgressHelper:= TSyncDirsDlgProgressHelper.Create(
    False,
    pnlFileCountProgress,
    lblFileCountProgress,
    pbFileCountProgress);

  { settings }
  chkEmptyDir.Checked    := gSyncDirsEmptyDirs;
  chkSubDirs.Checked     := gSyncDirsSubdirs;
  chkAsymmetric.Checked  := gSyncDirsAsymmetric;
  chkByContent.Checked   := gSyncDirsByContent and chkByContent.Enabled;
  chkIgnoreDate.Checked  := gSyncDirsIgnoreDate;
  sbCopyRight.Down       := gSyncDirsShowFilterCopyRight;
  sbEqual.Down           := gSyncDirsShowFilterEqual;
  sbNotEqual.Down        := gSyncDirsShowFilterNotEqual;
  sbUnknown.Down         := gSyncDirsShowFilterUnknown;
  sbCopyLeft.Down        := gSyncDirsShowFilterCopyLeft;
  sbDuplicates.Down      := gSyncDirsShowFilterDuplicates;
  sbSingles.Down         := gSyncDirsShowFilterSingles;
  if gSyncDirsFileMaskSave = False then
  begin
    Index := glsSyncMaskHistory.IndexOf(gSyncDirsFileMask);
    if Index <> -1 then
      glsSyncMaskHistory.Move(Index, 0)
    else
      glsSyncMaskHistory.Insert(0, gSyncDirsFileMask);
  end;
  cbExtFilter.Items.Assign(glsSyncMaskHistory);
  cbExtFilter.Text       := gSyncDirsFileMask;
  cbExcludeDirs.Items.Assign(glsSearchExcludeDirectories);
  cbExcludeDirs.Text     := gSyncDirsExcludeDirs;
  cbExcludeFiles.Items.Assign(glsSearchExcludeFiles);
  cbExcludeFiles.Text    := gSyncDirsExcludeFiles;
  UpdateExcludeFieldsState;
  chkViewFiles.Checked   := gSyncDirsViewFiles;
  chkViewIndent.Checked  := gSyncDirsViewIndent;
  chkActionsSubfolders.Checked := gSyncDirsActionsSubfolders;
  applyViewSettings;
  setViewLevel(gSyncDirsViewLevel);
  {$IF DEFINED(LCLGTK2)}
  ShowDropDownAsList(cbViewLevel);
  {$ENDIF}
  UpdateStatusBar;

  HMSync := HotMan.Register(Self, HotkeysCategory);
  HMSync.RegisterActionList(ActionList);
  FCommands := TFormCommands.Create(Self, ActionList);
  ResetDeleteOptions;

{$IFDEF DARWIN}
  self.BorderIcons:= self.BorderIcons - [biMinimize];
{$ENDIF}
end;

procedure TfrmSyncDirsDlg.FormResize(Sender: TObject);
begin
  pbFileSizeProgress.Width:= ClientWidth div 3;
  pbFileCountProgress.Width:= pbFileSizeProgress.Width;
end;

// The grid shows the folder view (FView), not the flat list: a grid row is
// mapped to its flat-list row; folder rows have their own layout and do not
// size the file columns
procedure TfrmSyncDirsDlg.MainDrawGridGetCellPreferedWidth(
  const Sender: TObject;
  const aCol: Integer;
  const aRow: Integer;
  var preferedWidth: Integer);
var
  viewRow: TSyncViewRow;
  s: String;
begin
  preferedWidth:= 0;
  if (FView = nil) or (aRow < 0) or (aRow >= FView.Count) then
    Exit;
  viewRow:= FView.row(aRow);
  if viewRow.kind <> vrFile then
    Exit;

  s:= getDisplayText(aCol, viewRow.rowIndex);
  if s = EmptyStr then
    Exit;

  preferedWidth:= MainDrawGrid.Canvas.TextWidth(s);
  case aCol of
    0: Inc(preferedWidth, 2 + LEFT_FILE_INDENTATION + rowIndentation(viewRow.depth) + 2);
    6: Inc(preferedWidth, 2 + rowIndentation(viewRow.depth) + 2);
    1, 5: Inc(preferedWidth, 2 + 8);
    2, 4: Inc(preferedWidth, 2 + 2);
  end;
end;

procedure TfrmSyncDirsDlg.MainDrawGridDblClick(Sender: TObject);
var
  r, x: Integer;
  viewRow: TSyncViewRow;
  rec: TSyncRec;
begin
  r := MainDrawGrid.Row;
  if (r < 0) or (r >= FView.Count) then Exit;
  viewRow := FView.row(r);
  if viewRow.kind <> vrFile then
  begin
    toggleFolderRow(r);
    Exit;
  end;
  x := MainDrawGrid.ScreenToClient(Mouse.CursorPos).X;
  if (x > hCols[3].Left) and (x < hCols[3].Left + hCols[3].Width) then Exit;
  rec := viewRow.rec;
  if rec.isDir or NOT rec.hasFilesOnBothSides or (rec.state = srsEqual) then
    Exit;
  PrepareToolData(self.leftFS, rec.leftFile, self.rightFS, rec.rightFile, @ShowDifferByGlobList);
end;

// The summary a folder row shows: what is beneath it, by direction
function folderSummaryText(const summary: TSyncDirSummary): String;
  procedure part(const count: Integer; const what: String);
  begin
    if count > 0 then
      Result := Result + '  ' + IntToStrTS(count) + ' ' + what;
  end;
begin
  Result := '';
  part(summary.copyToRight, '->');
  part(summary.copyToLeft, '<-');
  part(summary.deleteLeft, 'del <');
  part(summary.deleteRight, 'del >');
  part(summary.conflicts, '!');
  part(summary.unreadable, rsSyncUnreadable);
  part(summary.equal, '=');
  part(summary.undecided, 'skip');
end;

// Red: something inside is left alone whatever the action (a conflict or
// an unreadable folder); the "unknown" colour: newer files on both sides,
// the folder to look at file by file
function folderRowColor(const viewRow: TSyncViewRow; const summary: TSyncDirSummary): TColor;
begin
  if viewRow.rec.isUnreadable or (summary.unreadable > 0) or (summary.conflicts > 0) then
    Result := clRed
  else if summary.changedOnBothSides then
    Result := gColors.SyncDirs^.UnknownColor
  else
    Result := clWindowText;
end;

function fileRowColor(const rec: TSyncRec): TColor;
begin
  if rec.isTypeConflict then
    Exit(clRed);
  with gColors.SyncDirs^ do
    case rec.state of
      srsNotEq:       Result := UnknownColor;
      srsCopyToLeft:  Result := RightColor;
      srsCopyToRight: Result := LeftColor;
      srsDeleteLeft:  Result := LeftColor;
      srsDeleteRight: Result := RightColor;
      else            Result := clWindowText;
    end;
end;

procedure TfrmSyncDirsDlg.drawFolderRow(const viewRow: TSyncViewRow;
  const summary: TSyncDirSummary; const aRect: TRect; const aState: TGridDrawState);
const
  FOLD_MARKER: array[Boolean] of String = ('[-] ', '[+] ');
var
  folderText: String;
begin
  with MainDrawGrid.Canvas do
  begin
    if gdSelected in aState then
      Brush.Color := gColors.SyncDirs^.DirSelectedColor
    else
      Brush.Color := {$IFDEF DARWIN}clInfoBk{$ELSE}clBtnFace{$ENDIF};
    FillRect(aRect);
    Font.Bold := True;
    Font.Color := folderRowColor(viewRow, summary);
    folderText := FOLD_MARKER[viewRow.kind = vrFoldedFolder] + folderRowName(viewRow.dirIndex);
    with hCols[0] do
      TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
        Left + 2 + rowIndentation(viewRow.depth), aRect.Top + 2, folderText);
    with hCols[1] do
      TextRect(Rect(Left, aRect.Top, hCols[2].Left + hCols[2].Width, aRect.Bottom),
        Left + 2, aRect.Top + 2, folderSummaryText(summary));
    if viewRow.rec.isUnreadableOnSide(dsRight) then
      with hCols[4] do
        TextRect(Rect(Left, aRect.Top, hCols[5].Left + hCols[5].Width, aRect.Bottom),
          Left + 2, aRect.Top + 2, rsSyncUnreadable);
  end;
end;

procedure TfrmSyncDirsDlg.drawFileRow(const viewRow: TSyncViewRow; const aRect: TRect);
var
  rec: TSyncRec;
  fileName: String;
  indent: Integer;
begin
  rec := viewRow.rec;
  MainDrawGrid.Canvas.Font.Color := fileRowColor(rec);
  fileName := FFilteredList.path(viewRow.rowIndex);
  indent := rowIndentation(viewRow.depth);
  if rec.hasLeftFile then
    drawFileSide(rec.leftFile, fileName, 0, 1, 2, LEFT_FILE_INDENTATION + indent, aRect);
  if rec.hasRightFile then
    drawFileSide(rec.rightFile, fileName, 6, 5, 4, indent, aRect);
end;

// One side of a file row: the fileName, the size right-aligned, the date
procedure TfrmSyncDirsDlg.drawFileSide(const aFile: TFile; const fileName: String;
  const nameCol, sizeCol, dateCol, indent: Integer; const aRect: TRect);
var
  s: String;
begin
  with MainDrawGrid.Canvas do
  begin
    with hCols[nameCol] do
      TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
        Left + 2 + indent, aRect.Top + 2, fileName);
    s := IntToStrTS(aFile.Size);
    with hCols[sizeCol] do
      TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
        Left + Width - 8 - TextWidth(s), aRect.Top + 2, s);
    s := FormatDateTime(gDateTimeFormatSync, aFile.ModificationTime);
    with hCols[dateCol] do
      TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
        Left + 2, aRect.Top + 2, s);
  end;
end;

procedure TfrmSyncDirsDlg.drawActionIcon(const rowAction: TSyncRecState; const aRect: TRect);
begin
  ImageList1.Draw(MainDrawGrid.Canvas,
    hCols[3].Left + (hCols[3].Width - ImageList1.Width) div 2 - 2,
    (aRect.Top + aRect.Bottom - ImageList1.Height - 1) div 2, Ord(rowAction));
end;

// The folder's own rowAction (empty directories), else the one rowAction
// everything beneath shares
function TfrmSyncDirsDlg.folderRowAction(const viewIndex: Integer): TSyncRecState;
begin
  Result := FView.row(viewIndex).rec.action;
  if Result = srsDoNothing then
    Result := FView.summaryOf(viewIndex).singleAction;
end;

procedure TfrmSyncDirsDlg.MainDrawGridDrawCell(Sender: TObject; aCol,
  aRow: Integer; aRect: TRect; aState: TGridDrawState);
var
  viewRow: TSyncViewRow;
  rowAction: TSyncRecState;
begin
  if (FView = nil) or (aRow >= FView.Count) then Exit;
  viewRow := FView.row(aRow);
  if viewRow.kind = vrFile then
  begin
    drawFileRow(viewRow, aRect);
    drawActionIcon(viewRow.rec.action, aRect);
    Exit;
  end;
  drawFolderRow(viewRow, FView.summaryOf(aRow), aRect, aState);
  rowAction := folderRowAction(aRow);
  if rowAction <> srsDoNothing then
    drawActionIcon(rowAction, aRect);
end;

// Opens or closes the folder under the cursor when it is of that kind
function TfrmSyncDirsDlg.toggleCursorFolder(const kind: TSyncViewRowKind): Boolean;
var
  r: Integer;
begin
  r := MainDrawGrid.Row;
  Result := (r >= 0) and (r < FView.Count) and (FView.row(r).kind = kind);
  if Result then
    toggleFolderRow(r);
end;

procedure TfrmSyncDirsDlg.MainDrawGridKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  ASelection: TGridRect;
begin
  case Key of
    VK_SPACE:
      begin
        toggleSelectionAction;
        Key:= 0;
      end;
    VK_RIGHT, VK_ADD:
      if toggleCursorFolder(vrFoldedFolder) then
        Key:= 0;
    VK_LEFT, VK_SUBTRACT:
      if toggleCursorFolder(vrFolder) then
        Key:= 0;
    VK_MULTIPLY:
      begin
        foldAllAt(0);
        Key:= 0;
      end;
    VK_DIVIDE:
      begin
        foldAllAt(1);
        Key:= 0;
      end;
    VK_A:
      if (Shift = [ssModifier]) then
      begin
        ASelection.Top:= 0;
        ASelection.Left:= 0;
        ASelection.Right:= MainDrawGrid.ColCount - 1;
        ASelection.Bottom:= MainDrawGrid.RowCount - 1;
        MainDrawGrid.Selection:= ASelection;
        Key:= 0;
      end;
    VK_C,
    VK_INSERT:
      if (Shift = [ssModifier]) then
      begin
        CopyToClipboard;
        Key:= 0;
      end;
  end;
end;

procedure TfrmSyncDirsDlg.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  noOperation: Boolean;
begin
  if Key <> VK_ESCAPE then
    Exit;

  Key := 0;
  noOperation:= NOT self.stopOperation;
  if noOperation then
    Close;
end;

procedure TfrmSyncDirsDlg.HeaderDGHeaderClick(Sender: TObject;
  IsColumn: Boolean; Index: Integer);
begin
  if (Index <> 3) and (Index <= 6) then
    SortIndex := Index;
end;

procedure TfrmSyncDirsDlg.HeaderDGHeaderSizing(sender: TObject;
  const IsColumn: boolean; const aIndex, aSize: Integer);
var
  column: TGridColumn;
begin
  column:= HeaderDG.Columns[aIndex];
  if aSize < column.MinSize then
    column.Width:= column.MinSize;
  RecalcHeaderCols;
  MainDrawGrid.Invalidate;
end;

procedure TfrmSyncDirsDlg.HeaderDGHeaderSized(Sender: TObject;
  IsColumn: Boolean; Index: Integer);
var
  column: TGridColumn;
begin
  column:= HeaderDG.Columns[Index];
  if column.Width < column.MinSize then
    column.Width:= column.MinSize;
  RecalcHeaderCols;
  MainDrawGrid.Invalidate;
end;

procedure TfrmSyncDirsDlg.HeaderDGGetColumnPreferedWidth(
  const Sender: TObject;
  const aCol: Integer;
  var preferedWidth: Integer);
begin
  preferedWidth:= MainDrawGrid.calcPreferedWidth(aCol);
end;

procedure TfrmSyncDirsDlg.FilterSpeedButtonClick(Sender: TObject);
begin
  FillFoundItemsDG;
end;

procedure TfrmSyncDirsDlg.MenuItemViewClick(Sender: TObject);
var
  r: Integer;
  f: TFile = nil;
  rec: TSyncRec;
begin
  r := MainDrawGrid.Row;
  if (r < 0) or (r >= FView.Count) then Exit;
  rec := FView.row(r).rec;
  if rec.isFile then
  begin
    if Sender = MenuItemViewLeft then
      f := rec.leftFile
    else if Sender = MenuItemViewRight then begin
      f := rec.rightFile;
    end;
    if Assigned(f) then ShowViewerByGlob(f.FullPath);
  end;
end;

procedure TfrmSyncDirsDlg.pmGridMenuPopup(Sender: TObject);
  procedure calcSelection;
  var
    fromIndex: Integer;
    toIndex: Integer;
  begin
    fromIndex:= MainDrawGrid.Row;
    // A folder row under the cursor is always selected with what the action
    // will reach, so a change of the subfolders option shows at once; a
    // selection made by hand elsewhere is kept
    if (fromIndex < 0) or (fromIndex >= FView.Count) then
      Exit;
    if FView.row(fromIndex).kind = vrFile then begin
      if MainDrawGrid.HasMultiSelection then
        Exit;
      if MainDrawGrid.Selection.Height>0 then
        Exit;
    end;

    toIndex:= FView.lastRowUnder( fromIndex );
    MainDrawGrid.Selection:= TGridRect.Create(0,fromIndex,3,toIndex);
  end;

  procedure enableMenuItems;
  var
    indexes: TIntegerList;
    hasBothWithinSameRec: Boolean;
    leftCount: Integer;
    rightCount: Integer;
    hasLeft: Boolean;
    hasRight: Boolean;
    hasBoth: Boolean;
    enableCopyProperties: Boolean;
  begin
    indexes:= self.createSelectionIndexes;
    FFilteredList.countLeftRight(indexes, leftCount, rightCount);
    hasBothWithinSameRec:= FFilteredList.countBothSides(indexes) > 0;
    indexes.Free;

    hasLeft:= (leftCount > 0);
    hasRight:= (rightCount > 0);
    hasBoth:= hasLeft AND hasRight;

    enableCopyProperties:= hasBothWithinSameRec;
    if enableCopyProperties then
      enableCopyProperties:= TSyncDirsUtil.supportsCopyProperties(FFileSources);

    miSelectCopyLeftToRight.Enabled:= hasLeft;
    miSelectCopyRightToLeft.Enabled:= hasRight;
    miSelectKeepLink.Visible:= FFilteredCountRec.typeConflict > 0;
    MenuItemViewLeft.Enabled:= hasLeft;
    MenuItemViewRight.Enabled:= hasRight;
    MenuItemCompare.Enabled:= hasBothWithinSameRec;
    miCopyPropertiesLeftToRight.Enabled:= enableCopyProperties;
    miCopyPropertiesRightToLeft.Enabled:= enableCopyProperties;
    miSelectDeleteLeft.Enabled := hasLeft;
    miSelectDeleteRight.Enabled := hasRight;
    miSelectDeleteBoth.Enabled := hasBoth;
    miDeleteLeft.Enabled := hasLeft;
    miDeleteRight.Enabled := hasRight;
    miDeleteBoth.Enabled := hasBoth;
  end;
begin
  calcSelection;
  enableMenuItems;
end;

procedure TfrmSyncDirsDlg.TimerTimer(Sender: TObject);
var
  CopyStatistics: TFileSourceCopyOperationStatistics;
  DeleteStatistics: TFileSourceDeleteOperationStatistics;
begin
  if Assigned(FOperation) then begin
    if (FOperation is TFileSourceCopyOperation) then begin
      CopyStatistics:= TFileSourceCopyOperation(FOperation).RetrieveStatistics;
      FFileSizeProgressHelper.done:= FCopyStatistics.DoneBytes + CopyStatistics.DoneBytes;
    end else if (FOperation is TFileSourceDeleteOperation) then begin
      DeleteStatistics:= TFileSourceDeleteOperation(FOperation).RetrieveStatistics;
      FFileCountProgressHelper.done:= FDeleteStatistics.DoneFiles + DeleteStatistics.DoneFiles;
    end;
  end;

  if FState.isRunningInState(sddsCheckingContent) then begin
    CopyStatistics:= FCheckContentThread.RetrieveStatistics;
    checkContentThreadUpdateStat(CopyStatistics.DoneBytes, CopyStatistics.TotalBytes);
  end;

  FFileSizeProgressHelper.updateBarControl;
  FFileCountProgressHelper.updateBarControl;
end;

function TfrmSyncDirsDlg.createCompareOption: TSyncDirsCompareOption;
var
  flags: TSyncDirsCompareFlags;
begin
  flags:= [];
  if self.chkOnlySelected.Checked then
    Include( flags, TSyncDirsCompareFlag.cfOnlySelected );
  if self.chkEmptyDir.Checked then
    Include( flags, TSyncDirsCompareFlag.cfEmptyDirs );
  if self.chkAsymmetric.Checked then
    Include( flags, TSyncDirsCompareFlag.cfAsymmetric );
  if self.chkSubDirs.Checked then
    Include( flags, TSyncDirsCompareFlag.cfSubdirs );
  if self.chkByContent.Checked then
    Include( flags, TSyncDirsCompareFlag.cfByContent );
  if self.chkIgnoreDate.Checked then
    Include( flags, TSyncDirsCompareFlag.cfIgnoreDate );

  if TSyncDirsUtil.isBothFileSystemFileSource(FFileSources) then begin
    if gNtfsHourTimeDelay and NtfsHourTimeDelay(self.edPath1.Text, self.edPath2.Text) then
      Include( flags, TSyncDirsCompareFlag.cfNtfsShift );
  end;

  Result:= TSyncDirsCompareOption.Create( flags );
end;

function TfrmSyncDirsDlg.createFilterFlags: TFilterFlags;
begin
  Result:= [];
  if self.sbCopyRight.Down then
    Include( Result, TSyncDirsFilterFlag.ffCopyRight );
  if self.sbCopyLeft.Down then
    Include( Result, TSyncDirsFilterFlag.ffCopyLeft );
  if self.sbEqual.Down then
    Include( Result, TSyncDirsFilterFlag.ffEqual );
  if self.sbNotEqual.Down then
    Include( Result, TSyncDirsFilterFlag.ffNotEqual );
  if self.sbUnknown.Down then
    Include( Result, TSyncDirsFilterFlag.ffUnknown );
  if self.sbDuplicates.Down then
    Include( Result, TSyncDirsFilterFlag.ffDuplicate );
  if self.sbSingles.Down then
    Include( Result, TSyncDirsFilterFlag.ffSingle );
end;

// The row list indexes behind the selected grid rows: a folder row stands
// for the rows beneath it
function TfrmSyncDirsDlg.createSelectionIndexes: TIntegerList;
var
  i: Integer;
  viewIndexes: TIntegerList;
begin
  Result:= TIntegerList.Create;
  viewIndexes:= TIntegerList.Create;
  try
    for i:= 0 to self.MainDrawGrid.RowCount-1 do begin
      if MainDrawGrid.IsCellSelected[0,i] then
        viewIndexes.Add( i );
    end;
    FView.rowListIndexes( viewIndexes, Result );
  finally
    viewIndexes.Free;
  end;
end;

procedure TfrmSyncDirsDlg.applyViewSettings;
begin
  FView.showFiles := chkViewFiles.Checked;
  FView.actionsIncludeSubfolders := chkActionsSubfolders.Checked;
end;

// Rebuild the grid rows from the row list, keeping the cursor in range
procedure TfrmSyncDirsDlg.refreshView;
var
  r: Integer;
begin
  r := MainDrawGrid.Row;
  FView.build;
  MainDrawGrid.RowCount := FView.Count;
  if (FView.Count > 0) and (r >= 0) then
    MainDrawGrid.Row := Min(r, FView.Count - 1);
  MainDrawGrid.Invalidate;
end;

// Rebuild after the folds changed, keeping the cursor on the same file or
// folder, or on the folded folder it went into
procedure TfrmSyncDirsDlg.refoldView;
var
  r: Integer;
  current: TSyncViewRow;
  hadRow: Boolean;
begin
  r := MainDrawGrid.Row;
  hadRow := (r >= 0) and (r < FView.Count);
  if hadRow then
    current := FView.row(r);
  FView.build;
  MainDrawGrid.RowCount := FView.Count;
  if hadRow and (FView.Count > 0) then
    MainDrawGrid.Row := FView.rowShowing(current);
  MainDrawGrid.Invalidate;
end;

procedure TfrmSyncDirsDlg.toggleFolderRow(const viewIndex: Integer);
begin
  if (viewIndex < 0) or (viewIndex >= FView.Count) then Exit;
  if FView.row(viewIndex).kind = vrFile then Exit;
  FView.toggle(viewIndex);
  MainDrawGrid.RowCount := FView.Count;
  MainDrawGrid.Row := viewIndex;
  MainDrawGrid.Invalidate;
end;

// Level 0 = all levels; the list's item index is the level
procedure TfrmSyncDirsDlg.setViewLevel(const level: Integer);
var
  shown: Integer;
begin
  shown := EnsureRange(level, 0, cbViewLevel.Items.Count - 1);
  if cbViewLevel.ItemIndex <> shown then
    cbViewLevel.ItemIndex := shown;
  if shown = FView.level then Exit;
  FView.level := shown;
  FView.forgetManualFolds;
  refoldView;
end;

// Every folder folded by the level again, the folds made by hand forgotten,
// also when the level is already the one asked for: 0 opens everything,
// 1 leaves only the top-level folders
procedure TfrmSyncDirsDlg.foldAllAt(const level: Integer);
begin
  if level <> FView.level then
    setViewLevel(level)
  else begin
    FView.forgetManualFolds;
    refoldView;
  end;
end;

procedure TfrmSyncDirsDlg.btnExpandAllClick(Sender: TObject);
begin
  foldAllAt(0);
  if MainDrawGrid.CanFocus then
    MainDrawGrid.SetFocus;
end;

procedure TfrmSyncDirsDlg.btnCollapseAllClick(Sender: TObject);
begin
  foldAllAt(1);
  if MainDrawGrid.CanFocus then
    MainDrawGrid.SetFocus;
end;

procedure TfrmSyncDirsDlg.cbViewLevelChange(Sender: TObject);
begin
  setViewLevel(cbViewLevel.ItemIndex);
end;

procedure TfrmSyncDirsDlg.chkViewFilesChange(Sender: TObject);
begin
  applyViewSettings;
  refreshView;
end;

procedure TfrmSyncDirsDlg.chkActionsSubfoldersChange(Sender: TObject);
begin
  applyViewSettings;
end;

procedure TfrmSyncDirsDlg.SetSortIndex(AValue: Integer);
  function getSortIndicator: String;
  begin
    {$IF DEFINED(MSWINDOWS) or DEFINED(DARWIN)}
    if FSortDesc then Result:= '↓' else Result:= '↑';
    {$ELSE}
    if FSortDesc then Result:= '↑' else Result:= '↓';
    {$ENDIF}
  end;

var
  s: string;
begin
  FSortService.sortIndex := AValue;
  if AValue = FSortIndex then
  begin
    s := HeaderDG.Columns[AValue].Title.Caption;
    UTF8Delete(s, 1, 1);
    FSortDesc := not FSortDesc;
    FSortService.sortDesc := FSortDesc;
    s := getSortIndicator() + s;
    HeaderDG.Columns[AValue].Title.Caption := s;
    FSortService.sortTree(FFullTree);
    FillFoundItemsDG;
  end else begin
    if FSortIndex >= 0 then
    begin
      s := HeaderDG.Columns[FSortIndex].Title.Caption;
      UTF8Delete(s, 1, 1);
      HeaderDG.Columns[FSortIndex].Title.Caption := s;
    end;
    FSortIndex := AValue;
    FSortDesc := False;
    FSortService.sortDesc := FSortDesc;
    with HeaderDG.Columns[FSortIndex].Title do
      Caption := getSortIndicator() + Caption;
    FSortService.sortTree(FFullTree);
    FillFoundItemsDG;
  end;
end;

procedure TfrmSyncDirsDlg.Compare;
begin
  TopPanel.Enabled := False;
  try
    FFullTree.Clear;
    FView.forgetManualFolds;
    FCompareOption.Free;
    FCompareOption:= self.createCompareOption;
    MainDrawGrid.RowCount := 0;
    ScanDirs;
    MainDrawGrid.SetFocus;
  finally
    TopPanel.Enabled := NOT FState.isRunningInState(sddsCheckingContent);
  end;
end;

procedure TfrmSyncDirsDlg.FillFoundItemsDG;
begin
  InitVisibleItems;
  FView.build;
  MainDrawGrid.ColCount := 1;
  MainDrawGrid.RowCount := FView.Count;
  MainDrawGrid.Invalidate;
  FFilteredCountRec:= FFilteredList.getCountRec;
  UpdateStatusBar;
  if FFullTree.Count > 0 then
  begin
    btnCompare.Default := False;
    btnSynchronize.Enabled := True;
    btnSynchronize.Default := True;
  end else begin
    btnCompare.Default := True;
    btnSynchronize.Enabled := False;
    btnSynchronize.Default := False;
  end;
end;

procedure TfrmSyncDirsDlg.InitVisibleItems;
begin
  TSyncDirsUtil.filterFlatListWithFlags(FFullTree, FFilteredList, self.createFilterFlags);
end;

procedure TfrmSyncDirsDlg.RecalcHeaderCols;
var
  i, l: Integer;
begin
  l := 0;
  for i := 0 to 6 do
    with hCols[i] do
    begin
      Left := l;
      Width := HeaderDG.Columns[i].Width;
      l := l + Width;
    end;
end;

procedure TfrmSyncDirsDlg.ScanDirs;
var
  builder: TSyncDirsTreeBuilder = nil;
  basePaths: TDoublePaths;
  // Non-nil only when FTemplate was built here from the exclude fields; a
  // template taken from gSearchTemplateList belongs to the list, not to us.
  ownTemplate: TSearchTemplate = nil;

  // Tell plugin file systems that a whole tree is about to be listed, as
  // Total Commander does (FS_STATUS_OP_SYNC_SEARCH), so they may fetch
  // ahead: over SFTP the compare otherwise waits out several round trips
  // per directory.
  procedure notifySyncSearch(const startEnd: Integer);
  var
    side: TDoubleSide;
    wfx: IWfxPluginFileSource;
    callbackData: TCallbackDataClass;
    oldProgress: TUpdateProgress = nil;
  begin
    for side := dsLeft to dsRight do
    begin
      if not Supports(FFileSources[side], IWfxPluginFileSource, wfx) then Continue;
      // Listing ahead can take seconds: the plugin then calls its progress
      // callback, which keeps the dialog responsive and lets Esc stop it
      callbackData:= TCallbackDataClass(WfxOperationList.Objects[wfx.PluginNumber]);
      if Assigned(callbackData) then
      begin
        oldProgress:= callbackData.UpdateProgressFunction;
        callbackData.UpdateProgressFunction:= @SyncSearchProgress;
      end;
      try
        wfx.WfxModule.WfxStatusInfo(basePaths[side], startEnd, FS_STATUS_OP_SYNC_SEARCH);
      finally
        if Assigned(callbackData) then
          callbackData.UpdateProgressFunction:= oldProgress;
      end;
    end;
  end;

  procedure setBaseDir(const text: String; const side: TDoubleSide);
  var
    path: String;
    address: String;
  begin
    path:= AppendPathDelim(text);
    address:= FAddresses[side];
    if (address <> '') and (Copy(path, 1, Length(address)) = address) then
      Delete(path, 1, Length(address));
    basePaths[side]:= path;
  end;

  procedure doScan;
  begin
    try
      if IsMaskSearchTemplate(cbExtFilter.Text) then
      begin
        FMaskList := nil;
        FTemplate:= gSearchTemplateList.TemplateByName[cbExtFilter.Text];
      end
      else begin
        ownTemplate := createExclusionTemplate;
        FTemplate := ownTemplate;
        if cbExtFilter.Text <> EmptyStr then
          FMaskList := TMaskList.Create(cbExtFilter.Text)
        else
          FMaskList := TMaskList.Create( '*' );
      end;
      FCmpFileSources := FFileSources;
      setBaseDir(edPath1.Text, dsLeft);
      setBaseDir(edPath2.Text, dsRight);
      FCmpFilePaths := basePaths;

      FScanShownPercent := 0;
      FLastMessagesTime := 0;
      builder:= TSyncDirsTreeBuilder.Create( self, FSortService, FCompareOption, FFileSources, basePaths );
      // Show "Comparing" before plugins start listing ahead
      commonCheckRunning( True );
      notifySyncSearch(FS_STATUS_START);
      try
        builder.build( FFullTree, FSelectedFiles );
      finally
        notifySyncSearch(FS_STATUS_END);
      end;

      if FState.isRunning then
        FCompareState := csCompared
      else
        FCompareState := csCancelled;
      FillFoundItemsDG;
    finally
      FreeAndNil(builder);
      FreeAndNil(FMaskList);
      FTemplate := nil;
      FreeAndNil(ownTemplate);
    end;
  end;

var
  abort: Boolean;
begin
  FState.enter(sddsScanning);
  doScan;
  abort:= NOT FState.isRunning;
  if FState.isInState(sddsScanning) then
    FState.reset;
  if abort then
    Exit;
  if (FFullTree.Count > 0) and (cfByContent in FCompareOption.flags) then
    checkContentThreadStart
end;

procedure TfrmSyncDirsDlg.UpdateStatusBar;
var
  s: string;
begin
  if FCompareState = csNotCompared then
  begin
    StatusBar1.Panels[0].Text := rsSyncNotCompared;
    Exit;
  end;
  s := Format(rsFilesFound, [FFilteredCountRec.total, FFilteredCountRec.equal, FFilteredCountRec.notEqual, FFilteredCountRec.leftUnique, FFilteredCountRec.rightUnique]);
  if FFilteredCountRec.unreadable > 0 then
    s := s + '  ' + Format(rsSyncFoldersUnreadable, [FFilteredCountRec.unreadable]);
  if FFilteredCountRec.typeConflict > 0 then
    s := s + '  ' + Format(rsSyncTypeConflicts, [FFilteredCountRec.typeConflict]);
  if FState.isRunningInState(sddsCheckingContent) then
    s := s + ' ...';
  if FCompareState = csCancelled then
    s := rsSyncCompareCancelled + '  ' + s;
  StatusBar1.Panels[0].Text := s;
end;

procedure TfrmSyncDirsDlg.toggleSelectionAction;
begin
  setSelectionAction(srsNextAction);
end;

procedure TfrmSyncDirsDlg.EnableControls(AEnabled: Boolean);
begin
  edPath1.Enabled:= AEnabled;
  edPath2.Enabled:= AEnabled;
  TopPanel.Enabled:= AEnabled;
  HeaderDG.Enabled:= AEnabled;
  pnlFilter.Enabled:= AEnabled;
  MainDrawGrid.Enabled:= AEnabled;
  pnlProgress.Visible:= not AEnabled;
  Timer.Enabled:= not AEnabled;
end;

procedure TfrmSyncDirsDlg.setSelectionAction(const newAction: TSyncRecState);
var
  indexes: TIntegerList;
begin
  indexes:= self.createSelectionIndexes;
  MainDrawGrid.BeginUpdate;
  try
    FFilteredList.setNewAction( indexes, newAction );
  finally
    indexes.Free;
    MainDrawGrid.EndUpdate;
  end;
  refreshView;
end;

function TfrmSyncDirsDlg.stopOperation: Boolean;
begin
  Result:= FState.isRunning;
  if NOT Result then
    Exit;
  FState.stop;
  if Assigned(FOperation) then
    FOperation.Stop;
end;

procedure TfrmSyncDirsDlg.doCopyProperties(const targetSide: TDoubleSide);
  function selectProperties: TCopyAttributesOptions;
  var
    dialog: TfrmSyncDirsSelectPropertiesDlg;
    properties: TfrmSelectFileProperties;
  begin
    Result:= [];
    dialog:= TfrmSyncDirsSelectPropertiesDlg.Create(nil);
    properties:= dialog.frmProperties;
    properties.chkTime.Checked:= gOperationOptionCopyTime;
    properties.chkAttributes.Checked:= gOperationOptionCopyAttributes;
    properties.chkPermissions.Checked:= gOperationOptionCopyOwnership or gOperationOptionCopyPermissions;
    properties.chkXAttributes.Checked:= gOperationOptionCopyXattributes;
    if dialog.ShowModal = mrOK then begin
      if properties.chkTime.Checked then
        Include(Result, caoCopyTime);
      if properties.chkAttributes.Checked then
        Include(Result, caoCopyAttributes);
      if properties.chkPermissions.Checked then
        Result:= Result + [caoCopyPermissions, caoCopyOwnership];
      if properties.chkXAttributes.Checked then
        Include(Result, caoCopyXattributes);
    end;
    dialog.Free;
  end;

var
  commonService: TSyncDirsCommonService;
  indexes: TIntegerList = nil;
  attrs: TCopyAttributesOptions;
begin
  attrs:= selectProperties;
  if attrs = [] then
    Exit;

  commonService:= TSyncDirsCommonService.Create(self, self, FFilteredList, FCmpFileSources);
  try
    indexes:= self.createSelectionIndexes;

    FState.enter(sddsCopyingProperties);
    EnableControls(False);
    FFileSizeProgressHelper.close;
    FFileCountProgressHelper.open(rsOperSettingProperty, FFilteredList.countBothSides(indexes));

    commonService.copyProperties(indexes, targetSide, attrs);

    self.MainDrawGrid.Invalidate;
  finally
    if FState.isInState(sddsCopyingProperties) then begin
      FFileCountProgressHelper.close;
      EnableControls(True);
      FState.reset;
    end;
    commonService.Free;
    indexes.Free;
  end;
end;

function TfrmSyncDirsDlg.getDisplayText(const aCol: Integer; const aRow: Integer): String;
var
  rec: TSyncRec;
begin
  Result:= EmptyStr;
  rec:= FFilteredList.getSyncRec(aRow);
  case aCol of
    0: if rec.hasLeftFile then
         Result:= FFilteredList.path(aRow);
    1: if rec.hasLeftFile then
         Result:= IntToStrTS(rec.leftFile.Size);
    2: if rec.hasLeftFile then
         Result:= FormatDateTime(gDateTimeFormatSync, rec.leftFile.ModificationTime);
    4: if rec.hasRightFile then
         Result:= FormatDateTime(gDateTimeFormatSync, rec.rightFile.ModificationTime);
    5: if rec.hasRightFile then
         Result:= IntToStrTS(rec.rightFile.Size);
    6: if rec.hasRightFile then
         Result:= FFilteredList.path(aRow);
  end;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadStart;
begin
  Timer.Enabled:= True;
  HeaderDG.Enabled:= False;
  GroupBox1.Enabled:= False;
  MainDrawGrid.PopupMenu:= nil;
  pnlProgress.Visible:= True;
  FFileSizeProgressHelper.open(rsDiffComparing, 100);
  FFileCountProgressHelper.close;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadFinish;
begin
  Timer.Enabled:= False;
  FState.reset;
  if Assigned(FCheckContentThread) then begin
    FCheckContentThread.FreeOnTerminate:= True;
    FCheckContentThread:= nil;
  end;
  UpdateStatusBar;
  HeaderDG.Enabled:= True;
  TopPanel.Enabled:= True;
  GroupBox1.Enabled:= True;
  pnlProgress.Visible:= False;
  MainDrawGrid.PopupMenu:= pmGridMenu;
  MainDrawGrid.SetFocus;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadReapplyFilter;
begin
  FillFoundItemsDG;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadCountUpdated(
  const totalInc: Integer;
  const equalInc: Integer;
  const notEqInc: Integer);
begin
  Inc( FFilteredCountRec.total, totalInc );
  Inc( FFilteredCountRec.equal, equalInc );
  Inc( FFilteredCountRec.notEqual, notEqInc );
end;

procedure TfrmSyncDirsDlg.checkContentThreadStart;
begin
  if FState.isRunningInState(sddsCheckingContent) then
    Exit;
  FState.enter(sddsCheckingContent);
  FCheckContentThread := TSyncDirsCheckContentThread.Create(FFullTree, self.createFilterFlags, Self);
  FCheckContentThreadTimerCount := 0;
end;

procedure TfrmSyncDirsDlg.checkContentThreadStop;
begin
  if FCheckContentThread = nil then
    Exit;
  FCheckContentThread.Terminate;
  FCheckContentThread.WaitFor;    // onCheckContentThreadFinish() will be called
end;

procedure TfrmSyncDirsDlg.checkContentThreadUpdateStat(
  const doneBytes: Int64;
  const totalBytes: Int64 );
begin
  {$IFDEF LCLCOCOA}
  if totalBytes > 0 then
    FFileSizeProgressHelper.predefinedCaption := Format(rsComparingPercent, [doneBytes*100 div totalBytes])
  else
    FFileSizeProgressHelper.predefinedCaption := Format(rsComparingPercent, [0]);
  {$ENDIF}
  FFileSizeProgressHelper.total := totalBytes;
  FFileSizeProgressHelper.done := doneBytes;

  Inc(FCheckContentThreadTimerCount);
  if (FCheckContentThreadTimerCount mod 5 = 0) then begin
    refreshView;
    UpdateStatusBar;
  end;
end;

function TfrmSyncDirsDlg.treeBuilderMaskFilt(const f: TFile): Boolean;
begin
  if f.IsDirectory or f.IsLinkToDirectory then begin
    Result:= (FTemplate = nil) or (CheckDirectoryName(FTemplate.FileChecks, f.Name));
  end else begin
    // A file has to pass the template (named, or the exclude fields) and the
    // mask; the mask is no way around an exclusion
    Result:= ((FTemplate = nil) or FTemplate.CheckFile(f)) and
             ((FMaskList = nil) or FMaskList.Matches(f.Name));
  end;
end;

function TfrmSyncDirsDlg.treeBuilderUnreadable(const side: TDoubleSide;
  const path: String): TSyncDirsUnreadableAnswer;
begin
  case MsgBox(Format(rsSyncCannotRead, [FAddresses[side] + path]),
              [msmbRetry, msmbSkip, msmbSkipAll, msmbAbort], msmbRetry, msmbAbort) of
    mmrRetry:   Result:= uaRetry;
    mmrSkipAll: Result:= uaSkipAll;
    mmrAbort:
      begin
        stopOperation;
        Result:= uaAbort;
      end;
    else
      Result:= uaSkip;
  end;
end;

// A cancelled compare lists only part of the tree; folders that could not
// be read and type conflicts without an action are left alone on both
// sides; a conflict with an action replaces the other side. Say so before
// synchronizing.
function TfrmSyncDirsDlg.confirmSkippedItems(const syncCount: TSyncDirsSyncCount): Boolean;

  function warn(const message: String; const count: Integer): Boolean;
  begin
    Result:= (count = 0) or
             (MessageDlg(Format(message, [count]), mtWarning, [mbYes, mbNo], 0, mbNo) = mrYes);
  end;

begin
  Result:= warn(rsSyncCompareCancelledWarning, Ord(FCompareState = csCancelled)) and
           warn(rsSyncUnreadableWarning, FFilteredCountRec.unreadable) and
           warn(rsSyncTypeConflictWarning, syncCount.conflictKeepCount) and
           warn(rsSyncTypeConflictReplace, syncCount.conflictReplaceCount);
end;

procedure TfrmSyncDirsDlg.onTreeBuilderUpdateProgress(const percent: Integer);
begin
  FScanShownPercent := Max(FScanShownPercent, Min(99, percent));
end;

function TfrmSyncDirsDlg.commonCheckRunning(const processMessages: Boolean): Boolean;
begin
  // At most every 50 ms: a status bar update per directory is measurably
  // expensive on large trees, and so is pumping the message queue
  if processMessages and (GetTickCount64 - FLastMessagesTime >= 50) then
  begin
    FLastMessagesTime := GetTickCount64;
    if FState.isRunningInState(sddsScanning) then
      StatusBar1.Panels[0].Text := Format(rsComparingPercent, [FScanShownPercent]);
    Application.ProcessMessages;
  end;
  Result:= FState.isRunning;
end;

function TfrmSyncDirsDlg.SyncSearchProgress(SourceName, TargetName: PAnsiChar;
  PercentDone: Integer): Integer;
begin
  if commonCheckRunning( True ) then
    Result:= 0
  else
    Result:= 1;
end;

// Each run starts with fresh operation options, from the confirmation and
// the global settings; from here on they are carried from one batch to the
// next by the Apply*/Remember* pairs
procedure TfrmSyncDirsDlg.takeRunOptions(const dialog: TfrmSyncDirsPerformDlg);
begin
  // A link is always synced as a link; see TSyncDirsTreeBuilder.build
  SymLinkOption := fsooslDontFollow;
  if dialog.chkConfirmOverwrites.Checked then
    FileExistsOption := fsoofeNone
  else
    FileExistsOption := fsoofeOverwrite;
  VerifyOption := dialog.chkVerify.Checked;
  OverwriteReadOnly := dialog.chkOverwriteReadOnly.Checked;
  gSyncDirsOverwriteReadOnly := OverwriteReadOnly;
  SkipAllErrors := False;
  DirExistsOption := gOperationOptionDirectoryExists;
  SetPropertyError := gOperationOptionSetPropertyError;
  SkipFlags := Default(TFileSystemOperationHelperSkipFlags);
  ResetDeleteOptions;
  FDeleteToTrash := dialog.chkDeleteToTrash.Checked;
  gSyncDirsDeleteToTrash := FDeleteToTrash;
end;

// Whether the local trash can take what is deleted on this side
function TfrmSyncDirsDlg.trashAvailableOn(const side: TDoubleSide): Boolean;
begin
  Result:= FCmpFileSources[side].IsClass(TFileSystemFileSource) and
           mbCheckTrash(FCmpFilePaths[side]);
end;

procedure TfrmSyncDirsDlg.DeleteSelectedFiles(ALeft, ARight: Boolean);
var
  commonService: TSyncDirsCommonService;
  Message: String;
  indexes: TIntegerList = nil;
  leftCount: Integer;
  rightCount: Integer;
  fullyDone: Boolean;

  // Trash or delete is asked along with the confirmation when the trash is
  // available, preset from the last choice made in this dialog, and the
  // answer is kept for the next one
  function confirmed: Boolean;
  var
    trashAvailable: Boolean;
    dialogSource: IFileSource;
    deleteMode: TDeleteMode;
    queueId: TOperationsManagerQueueIdentifier;
  begin
    trashAvailable:= (NOT ALeft or trashAvailableOn(dsLeft)) and
                     (NOT ARight or trashAvailableOn(dsRight));
    if NOT trashAvailable then begin
      FDeleteToTrash:= False;
      Exit(MessageDlg(Message, mtWarning, [mbYes, mbNo], 0, mbYes) = mrYes);
    end;
    if ALeft then
      dialogSource:= FCmpFileSources[dsLeft]
    else
      dialogSource:= FCmpFileSources[dsRight];
    if FDeleteToTrash then
      deleteMode:= dmTrash
    else
      deleteMode:= dmDelete;
    Result:= ShowDeleteDialog(Self, Message, Message, EmptyStr,
               dialogSource, queueId, True, False, deleteMode);
    FDeleteToTrash:= (deleteMode = dmTrash);
    if Result then gSyncDirsDeleteToTrash:= FDeleteToTrash;
  end;

begin
  ResetDeleteOptions;
  commonService:= TSyncDirsCommonService.Create(self, self, FFilteredList, FCmpFileSources);
  try
    indexes:= self.createSelectionIndexes;
    FFilteredList.countLeftRight(indexes, leftCount, rightCount);

    ALeft:= ALeft and (leftCount > 0);
    ARight:= ARight and (rightCount > 0);

    if (ALeft = False) and (ARight = False) then Exit;

    FDeleteStatistics.DoneFiles:= 0;
    FDeleteStatistics.TotalFiles:= 0;

    Message:= EmptyStr;
    if ALeft then begin
      FDeleteStatistics.TotalFiles+= leftCount;
      Message:= Format(rsVarLeftPanel + ': ' + rsMsgDelFlDr, [leftCount]) + LineEnding;
    end;
    if ARight then begin
      FDeleteStatistics.TotalFiles+= rightCount;
      Message+= Format(rsVarRightPanel + ': ' + rsMsgDelFlDr, [rightCount]) + LineEnding;
    end;

    if confirmed then begin
      FState.enter(sddsDeletingFiles);
      EnableControls(False);
      FFileSizeProgressHelper.close;
      FFileCountProgressHelper.open(rsOperDeleting, FDeleteStatistics.TotalFiles);

      fullyDone:= commonService.delete(indexes, ALeft, ARight);
      if fullyDone then
        self.FillFoundItemsDG;

      if NOT fullyDone then
        btnCompare.Click;
    end;
  finally
    if FState.isInState(sddsDeletingFiles) then begin
      FFileCountProgressHelper.close;
      EnableControls(True);
      FState.reset;
    end;
    commonService.Free;
    indexes.Free;
  end;
end;

function TfrmSyncDirsDlg.fileProcessorWithUICopyFiles(
  const sourceFS: IFileSource;
  const targetFS: IFileSource;
  var files: TFiles;
  const targetPath: String): Boolean;
var
  supported: Boolean = False;

  procedure operationHandle( const operation: TFileSourceOperation; const state: TFileSourceOperationState );
  begin
    supported:= True;
    case state of
      fsosStarting: begin
        operation.Elevate:= ElevateAction;
        ApplyCopyOptions(operation);
        operation.AddUserInterface(FFileSourceOperationMessageBoxesUI);
        FOperation:= operation;
      end;
      fsosStopped: begin
        RememberCopyOptions(operation);
        FCopyStatistics.DoneBytes+= TFileSourceCopyOperation(operation).RetrieveStatistics.TotalBytes;
        FFileSizeProgressHelper.update(FCopyStatistics.DoneBytes);
        FOperation:= nil;
      end;
    end;
  end;

begin
  Result:= TSyncDirsUtil.copyFiles(sourceFS, targetFS, files, targetPath, @operationHandle );
  if NOT Result then begin
    if NOT supported then
      MessageDlg(rsMsgErrNotSupported, mtError, [mbOK], 0);
  end;
end;

function TfrmSyncDirsDlg.fileProcessorWithUIDeleteFiles(
  const FileSource: IFileSource;
  var Files: TFiles ): Boolean;
var
  supported: Boolean = False;

  procedure operationHandle( const operation: TFileSourceOperation; const state: TFileSourceOperationState );
  begin
    supported:= True;
    case state of
      fsosStarting: begin
        if (operation is TFileSystemDeleteOperation) then begin
          TFileSystemDeleteOperation(operation).Recycle:= FDeleteToTrash;
        end;
        ApplyDeleteOptions(operation);
        operation.Elevate:= ElevateAction;
        operation.AddUserInterface(FFileSourceOperationMessageBoxesUI);
        FOperation:= operation;
      end;
      fsosStopped: begin
        RememberDeleteOptions(operation);
        FDeleteStatistics.DoneFiles+= TFileSourceDeleteOperation(operation).RetrieveStatistics.TotalFiles;
        FFileCountProgressHelper.update(FDeleteStatistics.DoneFiles);
        FOperation:= nil;
      end;
    end;
  end;
begin
  Result:= TSyncDirsUtil.deleteFiles(FileSource, Files, @operationHandle);
  if NOT Result then begin
    if NOT supported then
      MessageDlg(rsMsgErrNotSupported, mtError, [mbOK], 0);
  end;
end;

function TfrmSyncDirsDlg.fileProcessorWithUICopyProperties(
  const targetFS: IFileSource;
  const sourceFile: TFile;
  const targetFile: TFile;
  const attrs: TCopyAttributesOptions ): Boolean;
var
  errMsg: String;
  askResult: TModalResult;
begin
  Result:= TSyncDirsUtil.copyProperties(targetFS, sourceFile, targetFile, attrs);
  Inc( FFileCountProgressHelper.done );
  if NOT Result then begin
    errMsg:= Format(rsMsgErrSetAttribute, [targetFile.FullPath]);
    askResult:= MessageDlg(errMsg, mtError, [mbIgnore, mbAbort], 0, mbAbort);
    Result:= (askResult = mrIgnore);
  end;
end;

{ Copy and delete operations are created anew for every directory batch, so
  the user's "All"-type answers (overwrite all, skip all errors, delete
  read-only, delete directly when the trash fails) live in form fields and are
  applied to each new operation and read back afterwards. }

procedure TfrmSyncDirsDlg.ApplyCopyOptions(const operation: TFileSourceOperation);
var
  copyOperation: TFileSourceCopyOperation absolute operation;
begin
  copyOperation.SymLinkOption := SymLinkOption;
  copyOperation.FileExistsOption := FileExistsOption;
  copyOperation.DirExistsOption := DirExistsOption;
  copyOperation.SkipAllErrors := SkipAllErrors;
  copyOperation.OverwriteReadOnly := OverwriteReadOnly;
  if operation is TFileSystemCopyOperation then
  begin
    TFileSystemCopyOperation(operation).Verify := VerifyOption;
    TFileSystemCopyOperation(operation).SetPropertyError := SetPropertyError;
    TFileSystemCopyOperation(operation).SkipFlags := SkipFlags;
  end
  else if operation is TWfxPluginCopyInOperation then
    TWfxPluginCopyInOperation(operation).SkipAllSpecialFiles := SkipFlags.SkipAllSpecialFiles;
end;

procedure TfrmSyncDirsDlg.RememberCopyOptions(const operation: TFileSourceOperation);
var
  copyOperation: TFileSourceCopyOperation absolute operation;
begin
  SymLinkOption := copyOperation.SymLinkOption;
  FileExistsOption := copyOperation.FileExistsOption;
  DirExistsOption := copyOperation.DirExistsOption;
  SkipAllErrors := copyOperation.SkipAllErrors;
  if operation is TFileSystemCopyOperation then
  begin
    SetPropertyError := TFileSystemCopyOperation(operation).SetPropertyError;
    SkipFlags := TFileSystemCopyOperation(operation).SkipFlags;
  end
  else if operation is TWfxPluginCopyInOperation then
  begin
    SkipFlags.SkipAllSpecialFiles := TWfxPluginCopyInOperation(operation).SkipAllSpecialFiles;
  end;
end;

// Answers given in one run must not leak into the next
procedure TfrmSyncDirsDlg.ResetDeleteOptions;
begin
  FDeleteSkipErrors := gSkipFileOpError;
  FDeleteReadOnlyOption := fsoogNone;
  FDeleteDirectlyOption := fsoogNone;
  FDeleteToTrash := gSyncDirsDeleteToTrash;
end;

procedure TfrmSyncDirsDlg.ApplyDeleteOptions(const operation: TFileSourceOperation);
var
  deleteOperation: TFileSourceDeleteOperation absolute operation;
begin
  deleteOperation.SkipErrors := FDeleteSkipErrors;
  deleteOperation.DeleteReadOnly := FDeleteReadOnlyOption;
  if operation is TFileSystemDeleteOperation then
    TFileSystemDeleteOperation(operation).DeleteDirectly := FDeleteDirectlyOption;
end;

procedure TfrmSyncDirsDlg.RememberDeleteOptions(const operation: TFileSourceOperation);
var
  deleteOperation: TFileSourceDeleteOperation absolute operation;
begin
  FDeleteSkipErrors := deleteOperation.SkipErrors;
  FDeleteReadOnlyOption := deleteOperation.DeleteReadOnly;
  if operation is TFileSystemDeleteOperation then
    FDeleteDirectlyOption := TFileSystemDeleteOperation(operation).DeleteDirectly;
end;

procedure TfrmSyncDirsDlg.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
                                             const AXProportion, AYProportion: Double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  RecalcHeaderCols;
end;

constructor TfrmSyncDirsDlg.Create(AOwner: TComponent; FileView1,
  FileView2: TFileView);
begin
  inherited Create(AOwner);
  FState := TSyncDirsDlgStateHelper.Create;
  FSortService := TSyncDirsSortService.Create;
  FFullTree := TTwoLevelTree.Create;
  FFilteredList := TFlatDirFileList.Create(FFullTree);
  FView := TSyncDirsView.Create(FFullTree, FFilteredList);
  self.leftFS := FileView1.FileSource;
  self.rightFS := FileView2.FileSource;
  self.leftAddress := FileView1.CurrentAddress;
  self.rightAddress := FileView2.CurrentAddress;
  with FileView1 do begin
    edPath1.Text := self.leftAddress + CurrentPath;
{$if lcl_fullversion >= 4990000}
    edPath1.DialogOptionsEx:= [ofShowsFilePackagesSwitch];
{$endif}
  end;
  with FileView2 do begin
    edPath2.Text := self.rightAddress + CurrentPath;
{$if lcl_fullversion >= 4990000}
    edPath2.DialogOptionsEx:= [ofShowsFilePackagesSwitch];
{$endif}
  end;
  RecalcHeaderCols;
  MainDrawGrid.DoubleBuffered := True;
  MainDrawGrid.Font.Bold := True;
  FSortIndex := -1;
  SortIndex := 0;
  MainDrawGrid.RowCount := 0;
  FSelectedFiles[dsLeft]:= FileView1.CloneSelectedFiles;
  FSelectedFiles[dsRight]:= FileView2.CloneSelectedFiles;
  chkOnlySelected.Enabled := ((FSelectedFiles[dsLeft].Count>0) or (FSelectedFiles[dsRight].Count>0)) and
                             (FileView1.FlatView = False) and
                             (FileView2.FlatView = False);
  chkOnlySelected.Checked := chkOnlySelected.Enabled;
  // ---------------------------------------------------------------------------
  chkByContent.Enabled := TSyncDirsUtil.supportsCompareByContent(FFileSources);
  chkAsymmetric.Enabled := fsoDelete in FileView2.FileSource.GetOperationsTypes;
  // ---------------------------------------------------------------------------
  actDeleteLeft.Enabled := fsoDelete in FileView1.FileSource.GetOperationsTypes;
  actDeleteRight.Enabled := fsoDelete in FileView2.FileSource.GetOperationsTypes;
  actDeleteBoth.Enabled := actDeleteLeft.Enabled and actDeleteRight.Enabled;
  // ---------------------------------------------------------------------------
  FFileSourceOperationMessageBoxesUI := TFileSourceOperationMessageBoxesUI.Create;
end;

destructor TfrmSyncDirsDlg.Destroy;
begin
  HotMan.UnRegister(Self);
  FFileSourceOperationMessageBoxesUI.Free;
  FSelectedFiles[dsLeft].Free;
  FSelectedFiles[dsRight].Free;
  FView.Free;
  FFilteredList.Free;
  FFullTree.Free;
  FSortService.Free;
  FCompareOption.Free;
  FFileSizeProgressHelper.Free;
  FFileCountProgressHelper.Free;
  FState.Free;
  inherited Destroy;
end;

procedure TfrmSyncDirsDlg.CopyToClipboard;
var
  indexes: TIntegerList = nil;
  sl: TStringList = nil;
begin
  try
    indexes:= self.createSelectionIndexes;
    sl:= TSyncDirsUtil.selectionToStringList(FFilteredList, indexes, FCompareOption);
    ClipboardSetText(sl.Text);
  finally
    FreeAndNil(sl);
    FreeAndNil(indexes);
  end;
end;

procedure TfrmSyncDirsDlg.cm_SelectClear(const Params: array of string);
begin
  setSelectionAction(srsDoNothing);
end;

procedure TfrmSyncDirsDlg.cm_SelectDeleteLeft(const Params: array of string);
begin
  setSelectionAction(srsDeleteLeft);
end;

procedure TfrmSyncDirsDlg.cm_SelectDeleteRight(const Params: array of string);
begin
  setSelectionAction(srsDeleteRight);
end;

procedure TfrmSyncDirsDlg.cm_SelectDeleteBoth(const Params: array of string);
begin
  setSelectionAction(srsDeleteBoth);
end;

procedure TfrmSyncDirsDlg.cm_SelectCopyDefault(const Params: array of string);
begin
  setSelectionAction(srsUnknown);
end;

procedure TfrmSyncDirsDlg.cm_SelectCopyReverse(const Params: array of string);
begin
  setSelectionAction(srsNotEq);
end;

procedure TfrmSyncDirsDlg.cm_SelectCopyLeftToRight(const Params: array of string);
begin
  setSelectionAction(srsCopyToRight);
end;

procedure TfrmSyncDirsDlg.cm_SelectCopyRightToLeft(const Params: array of string);
begin
  setSelectionAction(srsCopyToLeft);
end;

procedure TfrmSyncDirsDlg.cm_SelectKeepLink(const Params: array of string);
begin
  // Links are usually the original: the real folder on the other side came
  // from an earlier sync that copied what the link pointed to
  setSelectionAction(srsKeepLink);
end;

procedure TfrmSyncDirsDlg.cm_DeleteLeft(const Params: array of string);
begin
  DeleteSelectedFiles(True, False);
end;

procedure TfrmSyncDirsDlg.cm_DeleteRight(const Params: array of string);
begin
  DeleteSelectedFiles(False, True);
end;

procedure TfrmSyncDirsDlg.cm_DeleteBoth(const Params: array of string);
begin
  DeleteSelectedFiles(True, True);
end;

procedure TfrmSyncDirsDlg.cm_CopyPropertiesLeftToRight(const Params: array of string);
begin
  self.doCopyProperties(dsRight);
end;

procedure TfrmSyncDirsDlg.cm_CopyPropertiesRightToLeft(const Params: array of string);
begin
  self.doCopyProperties(dsLeft);
end;

initialization
  TFormCommands.RegisterCommandsForm(TfrmSyncDirsDlg, HotkeysCategory, @rsHotkeyCategorySyncDirs);

end.

