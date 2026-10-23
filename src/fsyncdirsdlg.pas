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
  { TDrawGrid }

  TDrawGrid = class(Grids.TDrawGrid)
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
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
    chkViewFiles: TCheckBox;
    btnExpandAll: TButton;
    btnCollapseAll: TButton;
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
    procedure chkViewFilesChange(Sender: TObject);
    procedure btnExpandAllClick(Sender: TObject);
    procedure btnCollapseAllClick(Sender: TObject);
    procedure chkActionsSubfoldersChange(Sender: TObject);
    procedure btnCompareClick(Sender: TObject);
    procedure btnSynchronizeClick(Sender: TObject);
    procedure edPath1AcceptDirectory(Sender: TObject; var Value: String);
    procedure RestoreProperties(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
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
    procedure FilterSpeedButtonClick(Sender: TObject);
    procedure MenuItemViewClick(Sender: TObject);
    procedure pmGridMenuPopup(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
  private
    FCommands: TFormCommands;
    FIniPropStorage: TIniPropStorageEx;
  private
    { private declarations }
    FCancel: Boolean;
    FScanning: Boolean;
    // Compare progress: shown at most every 50 ms, never going back
    FLastMessagesTime: QWord;
    FScanShownPercent: Integer;
    // The two source panels, so their directory watchers can be suspended
    // during bulk copy/delete (avoids one panel reload per ~100 changes)
    FFileViews: array [TDoubleSide] of TFileView;
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
    FFilteredCount: TSyncDirsFlatCount;
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

    FFileSizeProgressName: String;
    FFileSizeProgressTotal: Int64;
    FFileSizeProgressDone: Int64;
    FFileCountProgressName: String;
    FFileCountProgressTotal: Integer;
    FFileCountProgressDone: Integer;

    function createCompareOption: TSyncDirsCompareOption;
    function createFilterFlags: TFilterFlags;
    function createSelectionIndexes: TIntegerList;

    procedure toggleSelectionAction;
    procedure setSelectionAction(const newAction: TSyncRecState);

    procedure doCopyProperties(const targetSide: TDoubleSide);

    procedure updateFileCountProgress;

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
    procedure refreshView;
    procedure toggleFolderRow(const viewIndex: Integer);
    procedure drawFolderRow(const viewRow: TSyncViewRow; const summary: TSyncDirSummary;
                            const aRect: TRect; const aState: TGridDrawState);
    procedure SetPanelWatchers(AEnabled: Boolean);
    procedure ApplyCopyOptions(const operation: TFileSourceOperation);
    procedure RememberCopyOptions(const operation: TFileSourceOperation);
    procedure ResetDeleteOptions;
    procedure ApplyDeleteOptions(const operation: TFileSourceOperation);
    procedure RememberDeleteOptions(const operation: TFileSourceOperation);
    function trashAvailableOn(const side: TDoubleSide): Boolean;
    procedure SetProgressBytes(AProgressBar: TKASProgressBar; CurrentBytes: Int64; TotalBytes: Int64);
    procedure SetProgressFiles(AProgressBar: TKASProgressBar; CurrentFiles: Int64; TotalFiles: Int64);

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
    function fileProcessorWithUIDeleteFile(
      const FileSource: IFileSource;
      const f: TFile): Boolean;

  private
    FCheckContentThread: TSyncDirsCheckContentThread;
    FCheckContentThreadTimerCount: Integer;
    FCheckContentThreadComparing: Boolean;
  private
    procedure onCheckContentThreadStart;
    procedure onCheckContentThreadFinish;
    procedure onCheckContentThreadReapplyFilter;
    procedure onCheckContentThreadCountUpdated( const equalInc: Integer; const notEqInc: Integer );

    procedure checkContentThreadStart;
    procedure checkContentThreadStop;
    procedure checkContentThreadUpdateGrid;
    procedure checkContentThreadSetProgressBytes(const AProgressBar: TKASProgressBar; const CurrentBytes: Int64; const TotalBytes: Int64);

  private
    function treeBuilderCheckRunning( const processMessages: Boolean ): Boolean;
    function treeBuilderMaskFilt( const f: TFile ): Boolean;
    function treeBuilderUnreadable( const side: TDoubleSide; const path: String ): TSyncDirsUnreadableAnswer;
    procedure onTreeBuilderUpdateProgress( const percent: Integer );

  private
    function commonCheckRunning: Boolean;

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
  fMain, uDebug, fDiffer, fSyncDirsSelectPropertiesDlg,
  uGlobs, LCLType, LazUTF8, LazFileUtils,
  uFileSystemFileSource, DCDateTimeUtils,
  uDCUtils, uFileSourceOperationTypes, uShowForm, uAdministrator,
  uOSUtils, uLng, Math, uClipboard, fMaskInputDlg,
  LCLVersion, uTypes, uFileSystemCopyOperation, uFileSystemDeleteOperation, uFindFiles,
  uFileSourceManager, uFileSourceProperty, uShowMsg,
  fDeleteDlg, uTrash, uOperationsManager, uOSForms,
  uWfxPluginFileSource, WfxPlugin;

{$R *.lfm}

const
  GRID_COLUMN_FMT = 'HeaderDG_Column%d_Width';

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
  if Assigned(FOperation) then
    FOperation.Stop
  else if FCheckContentThreadComparing then
    checkContentThreadStop
  else begin
    pnlProgress.Hide;
  end;
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
  checkContentThreadStop;
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
    chkDeleteToTrash.Checked := gUseTrash;
    // A mirror keeps the empty folders the source has and loses the ones
    // it does not; deleting all of them on a side is no part of it
    chkDeleteLeftAllEmptyDirs.Visible := NOT chkAsymmetric.Checked;
    chkDeleteRightAllEmptyDirs.Visible := NOT chkAsymmetric.Checked;

    if ShowModal = mrOk then
    begin
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

      lblFileSizeProgress.Caption := rsOperCopying;
      lblFileCountProgress.Caption := rsOperDeleting;
      pbFileSizeProgress.Position:=0;
      pbFileCountProgress.Position:=0;
      pnlFileSizeProgress.Visible:= (sfCopyToLeft in syncFlags) or (sfCopyToRight in syncFlags);
      pnlFileCountProgress.Visible:= (sfDeleteLeft in syncFlags) or (sfDeleteRight in syncFlags) or
                                  (sfDeleteLeftAllEmptyDirs in syncFlags) or (sfDeleteRightAllEmptyDirs in syncFlags);

      SetPanelWatchers(False);
      try
        synchronizer.sync( syncFlags );
      finally
        SetPanelWatchers(True);
      end;

      EnableControls(True);
      btnCompare.Click;
    end;
  finally
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
  if (r < 0) or (r >= FView.Count)
  or (x - 2 < hCols[3].Left)
  or (x - 2 > hCols[3].Left + hCols[3].Width)
  then
    Exit;

  toggleSelectionAction;
end;

procedure TfrmSyncDirsDlg.RestoreProperties(Sender: TObject);
var
  Index: Integer;
begin
  with HeaderDG.Columns do
  begin
    for Index := 0 to Count - 1 do
      Items[Index].Width:= StrToIntDef(FIniPropStorage.StoredValue[Format(GRID_COLUMN_FMT, [Index])], Items[Index].Width);
  end;
  RecalcHeaderCols;
end;

procedure TfrmSyncDirsDlg.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
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
  gSyncDirsViewLevel            := cbViewLevel.ItemIndex;
  gSyncDirsViewFiles            := chkViewFiles.Checked;
  gSyncDirsActionsSubfolders    := chkActionsSubfolders.Checked;
  glsSyncMaskHistory.Assign(cbExtFilter.Items);
  // Exclusion history is shared with the Find files dialog: the same folder
  // and file patterns get skipped in both places.
  glsSearchExcludeDirectories.Assign(cbExcludeDirs.Items);
  glsSearchExcludeFiles.Assign(cbExcludeFiles.Items);

  with HeaderDG.Columns do
  begin
    for Index := 0 to Count - 1 do
      FIniPropStorage.StoredValue[Format(GRID_COLUMN_FMT, [Index])]:= IntToStr(Items[Index].Width);
  end;
end;

procedure TfrmSyncDirsDlg.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if Assigned(FOperation) then
  begin
    FOperation.Stop;
    CanClose := False;
  end
  else if FScanning then
  begin
    FCancel := True;
    CanClose := False;
  end
  else if FCheckContentThreadComparing then
  begin
    CanClose := False;
    checkContentThreadStop;
  end;
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

  {$IFDEF LCLCOCOA}
  pnlProgress.Color:=clBtnHighlight;
  {$ENDIF}
  MainDrawGrid.SelectedColor:= gColors.SyncDirs^.SelectedColor;

  lblFileSizeProgress.Caption    := rsOperCopying;
  lblFileCountProgress.Caption   := rsOperDeleting;
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
  cbViewLevel.ItemIndex  := Min(gSyncDirsViewLevel, cbViewLevel.Items.Count - 1);
  chkViewFiles.Checked   := gSyncDirsViewFiles;
  chkActionsSubfolders.Checked := gSyncDirsActionsSubfolders;
  applyViewSettings;

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
  if NOT rec.hasFilesOnBothSides or (rec.state = srsEqual) then
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

procedure TfrmSyncDirsDlg.drawFolderRow(const viewRow: TSyncViewRow;
  const summary: TSyncDirSummary; const aRect: TRect; const aState: TGridDrawState);
var
  folderText: String;
begin
  with MainDrawGrid.Canvas do
  begin
    if gdSelected in aState then
      Brush.Color := gColors.SyncDirs^.DirSelectedColor
    else begin
      {$IFDEF DARWIN}
      Brush.Color := clInfoBk;
      {$ELSE}
      Brush.Color := clBtnFace;
      {$ENDIF}
    end;
    FillRect(aRect);
    Font.Bold := True;
    if viewRow.rec.isUnreadable or (summary.unreadable > 0) or (summary.conflicts > 0) then
      Font.Color := clRed
    else if summary.changedOnBothSides then
      // Newer files on both sides: the folder to look at file by file
      Font.Color := gColors.SyncDirs^.UnknownColor
    else
      Font.Color := clWindowText;
    folderText := FFullTree.dirPath(viewRow.dirIndex) + PathDelim;
    if viewRow.kind = vrFoldedFolder then
      folderText := '[+] ' + folderText
    else
      folderText := '[-] ' + folderText;
    with hCols[0] do
      TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
        Left + 2, aRect.Top + 2, folderText);
    with hCols[1] do
      TextRect(Rect(Left, aRect.Top, hCols[2].Left + hCols[2].Width, aRect.Bottom),
        Left + 2, aRect.Top + 2, folderSummaryText(summary));
    if viewRow.rec.isUnreadableOnSide(dsRight) then
      with hCols[4] do
        TextRect(Rect(Left, aRect.Top, hCols[5].Left + hCols[5].Width, aRect.Bottom),
          Left + 2, aRect.Top + 2, rsSyncUnreadable);
  end;
end;

procedure TfrmSyncDirsDlg.MainDrawGridDrawCell(Sender: TObject; aCol,
  aRow: Integer; aRect: TRect; aState: TGridDrawState);
const
  LEFT_FILE_INDENTATION = 8;
var
  viewRow: TSyncViewRow;
  rec: TSyncRec;
  rowAction: TSyncRecState;
  x: Integer;
  s: string;
begin
  if (FView = nil) or (aRow >= FView.Count) then Exit;
  viewRow := FView.row(aRow);
  rec := viewRow.rec;
  with MainDrawGrid.Canvas do
  begin
    if viewRow.kind <> vrFile then
    begin
      drawFolderRow(viewRow, FView.summaryOf(aRow), aRect, aState);
      // The folder's own action (empty directories), else the one action
      // everything beneath shares
      rowAction := rec.action;
      if rowAction = srsDoNothing then
        rowAction := FView.summaryOf(aRow).singleAction;
    end else begin
      rowAction := rec.action;
      with gColors.SyncDirs^ do
      begin
        case rec.state of
        srsNotEq:       Font.Color := UnknownColor;
        srsCopyToLeft:    Font.Color := RightColor;
        srsCopyToRight:   Font.Color := LeftColor;
        srsDeleteLeft:  Font.Color := LeftColor;
        srsDeleteRight: Font.Color := RightColor;
        else Font.Color := clWindowText;
        end;
      end;
      if rec.isTypeConflict then Font.Color := clRed;
      if rec.hasLeftFile then
      begin
        with hCols[0] do
          TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
            Left + 2 + LEFT_FILE_INDENTATION, aRect.Top + 2, FFilteredList.path(viewRow.rowIndex));
        s := IntToStrTS(rec.leftFile.Size);
        with hCols[1] do begin
          x := Left + Width - 8 - TextWidth(s);
          TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
            x, aRect.Top + 2, s);
        end;
        s := FormatDateTime(gDateTimeFormatSync, rec.leftFile.ModificationTime);
        with hCols[2] do
          TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
            Left + 2, aRect.Top + 2, s)
      end;
      if rec.hasRightFile then
      begin
        TextOut(hCols[6].Left + 2, aRect.Top + 2, FFilteredList.path(viewRow.rowIndex));
        s := IntToStrTS(rec.rightFile.Size);
        with hCols[5] do begin
          x := Left + Width - 8 - TextWidth(s);
          TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
            x, aRect.Top + 2, s);
        end;
        s := FormatDateTime(gDateTimeFormatSync, rec.rightFile.ModificationTime);
        with hCols[4] do
          TextRect(Rect(Left, aRect.Top, Left + Width, aRect.Bottom),
            Left + 2, aRect.Top + 2, s)
      end;
    end;
    if (viewRow.kind = vrFile) or (rowAction <> srsDoNothing) then begin
      ImageList1.Draw(MainDrawGrid.Canvas,
        hCols[3].Left + (hCols[3].Width - ImageList1.Width) div 2 - 2,
        (aRect.Top + aRect.Bottom - ImageList1.Height - 1) div 2, Ord(rowAction));
    end;
  end;
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
      if (MainDrawGrid.Row >= 0) and (MainDrawGrid.Row < FView.Count) and
         (FView.row(MainDrawGrid.Row).kind = vrFoldedFolder) then
      begin
        toggleFolderRow(MainDrawGrid.Row);
        Key:= 0;
      end;
    VK_LEFT, VK_SUBTRACT:
      if (MainDrawGrid.Row >= 0) and (MainDrawGrid.Row < FView.Count) and
         (FView.row(MainDrawGrid.Row).kind = vrFolder) then
      begin
        toggleFolderRow(MainDrawGrid.Row);
        Key:= 0;
      end;
    VK_MULTIPLY:
      begin
        btnExpandAllClick(nil);
        Key:= 0;
      end;
    VK_DIVIDE:
      begin
        btnCollapseAllClick(nil);
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
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    if FScanning then
      FCancel := True
    else if FCheckContentThreadComparing then
      checkContentThreadStop
    else if pnlProgress.Visible then
      self.btnAbortClick(nil)
    else
      Close;
  end;
end;

procedure TfrmSyncDirsDlg.HeaderDGHeaderClick(Sender: TObject;
  IsColumn: Boolean; Index: Integer);
begin
  if (Index <> 3) and (Index <= 6) then
    SortIndex := Index;
end;

procedure TfrmSyncDirsDlg.HeaderDGHeaderSizing(sender: TObject;
  const IsColumn: boolean; const aIndex, aSize: Integer);
begin
  RecalcHeaderCols;
  MainDrawGrid.Invalidate;
end;

procedure TfrmSyncDirsDlg.FilterSpeedButtonClick(Sender: TObject);
begin
  FillFoundItemsDG
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
    if MainDrawGrid.HasMultiSelection then
      Exit;
    if MainDrawGrid.Selection.Height>0 then
      Exit;

    fromIndex:= MainDrawGrid.Row;
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
    miSelectKeepLink.Visible:= FFilteredCount.typeConflict > 0;
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
  if Assigned(FOperation) then
  begin
    if (FOperation is TFileSourceCopyOperation) then
    begin
      CopyStatistics:= TFileSourceCopyOperation(FOperation).RetrieveStatistics;
      SetProgressBytes(
        pbFileSizeProgress,
        FCopyStatistics.DoneBytes + CopyStatistics.DoneBytes,
        FCopyStatistics.TotalBytes);
    end
    else if (FOperation is TFileSourceDeleteOperation) then
    begin
      DeleteStatistics:= TFileSourceDeleteOperation(FOperation).RetrieveStatistics;
      SetProgressFiles(
        pbFileCountProgress,
        FDeleteStatistics.DoneFiles + DeleteStatistics.DoneFiles,
        FDeleteStatistics.TotalFiles);
    end;
  end
  else if FFileCountProgressName <> EmptyStr then
  begin
    updateFileCountProgress;
  end
  else if Assigned(FCheckContentThread) then
  begin
    Inc(FCheckContentThreadTimerCount);
    CopyStatistics:= FCheckContentThread.RetrieveStatistics;
    if (FCheckContentThreadTimerCount mod 5 = 0) then checkContentThreadUpdateGrid;
    checkContentThreadSetProgressBytes(pbFileSizeProgress, CopyStatistics.DoneBytes, CopyStatistics.TotalBytes);
  end;
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
  FView.level := cbViewLevel.ItemIndex;
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

procedure TfrmSyncDirsDlg.toggleFolderRow(const viewIndex: Integer);
begin
  if (viewIndex < 0) or (viewIndex >= FView.Count) then Exit;
  if FView.row(viewIndex).kind = vrFile then Exit;
  FView.toggle(viewIndex);
  MainDrawGrid.RowCount := FView.Count;
  MainDrawGrid.Row := viewIndex;
  MainDrawGrid.Invalidate;
end;

procedure TfrmSyncDirsDlg.cbViewLevelChange(Sender: TObject);
begin
  FView.forgetManualFolds;
  applyViewSettings;
  refreshView;
end;

procedure TfrmSyncDirsDlg.chkViewFilesChange(Sender: TObject);
begin
  applyViewSettings;
  refreshView;
end;

procedure TfrmSyncDirsDlg.btnExpandAllClick(Sender: TObject);
begin
  cbViewLevel.ItemIndex := 0;
  cbViewLevelChange(Sender);
end;

procedure TfrmSyncDirsDlg.btnCollapseAllClick(Sender: TObject);
begin
  cbViewLevel.ItemIndex := 1;
  cbViewLevelChange(Sender);
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
    TopPanel.Enabled := not FCheckContentThreadComparing;
  end;
end;

procedure TfrmSyncDirsDlg.FillFoundItemsDG;
begin
  InitVisibleItems;
  FView.build;
  MainDrawGrid.ColCount := 1;
  MainDrawGrid.RowCount := FView.Count;
  MainDrawGrid.Invalidate;
  FFilteredCount:= FFilteredList.flatCount;
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
  begin
    for side := dsLeft to dsRight do
      if Supports(FFileSources[side], IWfxPluginFileSource, wfx) then
        wfx.WfxModule.WfxStatusInfo(basePaths[side], startEnd, FS_STATUS_OP_SYNC_SEARCH);
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

begin
  FScanning := True;
  try
    FCancel := False;
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
    notifySyncSearch(FS_STATUS_START);
    try
      builder.build( FFullTree, FSelectedFiles );
    finally
      notifySyncSearch(FS_STATUS_END);
    end;

    FillFoundItemsDG;
    if FCancel then
      Exit;
    if (FFullTree.Count > 0) and (cfByContent in FCompareOption.flags) then
      checkContentThreadStart;
  finally
    FreeAndNil(builder);
    FreeAndNil(FMaskList);
    FTemplate := nil;
    ownTemplate.Free;
    FScanning := False;
  end;
end;

procedure TfrmSyncDirsDlg.UpdateStatusBar;
var s: string;
begin
  s := Format(rsFilesFound, [FFilteredCount.total, FFilteredCount.equal, FFilteredCount.notEqual, FFilteredCount.leftUnique, FFilteredCount.rightUnique]);
  if FFilteredCount.unreadable > 0 then
    s := s + '  ' + Format(rsSyncFoldersUnreadable, [FFilteredCount.unreadable]);
  if FFilteredCount.typeConflict > 0 then
    s := s + '  ' + Format(rsSyncTypeConflicts, [FFilteredCount.typeConflict]);
  if Assigned(FCheckContentThread)
  and not FCheckContentThread.Done then
    s := s + ' ...';
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

procedure TfrmSyncDirsDlg.doCopyProperties(const targetSide: TDoubleSide);
  function selectProperties: TCopyAttributesOptions;
  var
    dialog: TfrmSyncDirsSelectPropertiesDlg;
  begin
    Result:= [];
    dialog:= TfrmSyncDirsSelectPropertiesDlg.Create(nil);
    dialog.chkTime.Checked:= gOperationOptionCopyTime;
    dialog.chkAttributes.Checked:= gOperationOptionCopyAttributes;
    dialog.chkPermissions.Checked:= gOperationOptionCopyOwnership or gOperationOptionCopyPermissions;
    dialog.chkXAttributes.Checked:= gOperationOptionCopyXattributes;
    if dialog.ShowModal <> mrOK then
      Exit;

    if dialog.chkTime.Checked then
      Include(Result, caoCopyTime);
    if dialog.chkAttributes.Checked then
      Include(Result, caoCopyAttributes);
    if dialog.chkPermissions.Checked then
      Result:= Result + [caoCopyPermissions, caoCopyOwnership];
    if dialog.chkXAttributes.Checked then
      Include(Result, caoCopyXattributes);
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

    FFileCountProgressName:= rsOperSettingProperty;
    FFileCountProgressTotal:= FFilteredList.countBothSides(indexes);
    FFileCountProgressDone:= 0;

    EnableControls(False);
    pnlFileSizeProgress.Visible:= False;
    pnlFileCountProgress.Visible:= True;
    lblFileCountProgress.Caption:= FFileCountProgressName;
    pbFileCountProgress.Position:= 0;

    commonService.copyProperties(indexes, targetSide, attrs);

    self.MainDrawGrid.Invalidate;
    EnableControls(True);
  finally
    FFileCountProgressName:= EmptyStr;
    commonService.Free;
    indexes.Free;
  end;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadStart;
begin
  Timer.Enabled:= True;
  HeaderDG.Enabled:= False;
  GroupBox1.Enabled:= False;
  MainDrawGrid.Enabled:= False;
  pnlFileSizeProgress.Visible:= True;
  pbFileSizeProgress.SetProgress(0, 100);
  pnlFileCountProgress.Visible:= False;
  lblFileSizeProgress.Caption:= rsDiffComparing;
  pnlProgress.Visible:= True;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadFinish;
begin
  FCheckContentThreadComparing:= False;
  Timer.Enabled:= False;
  HeaderDG.Enabled:= True;
  TopPanel.Enabled:= True;
  GroupBox1.Enabled:= True;
  MainDrawGrid.Enabled:= True;
  pnlProgress.Visible:= False;
  MainDrawGrid.SetFocus;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadReapplyFilter;
begin
  FillFoundItemsDG;
  UpdateStatusBar;
end;

procedure TfrmSyncDirsDlg.onCheckContentThreadCountUpdated(
  const equalInc: Integer;
  const notEqInc: Integer);
begin
  Inc( FFilteredCount.equal, equalInc );
  Inc( FFilteredCount.notEqual, notEqInc );
end;

procedure TfrmSyncDirsDlg.checkContentThreadStart;
begin
  if Assigned(FCheckContentThread) then
    Exit;
  FCheckContentThread := TSyncDirsCheckContentThread.Create(FFullTree, Self);
  FCheckContentThreadTimerCount := 0;
  FCheckContentThreadComparing := True;
end;

procedure TfrmSyncDirsDlg.checkContentThreadStop;
begin
  if Assigned(FCheckContentThread) then
  begin
    with FCheckContentThread do
    begin
      Terminate;
      WaitFor;
    end;
    FreeAndNil(FCheckContentThread);
  end;
end;

procedure TfrmSyncDirsDlg.checkContentThreadUpdateGrid;
begin
  refreshView;
  UpdateStatusBar;
end;

procedure TfrmSyncDirsDlg.checkContentThreadSetProgressBytes(
  const AProgressBar: TKASProgressBar;
  const CurrentBytes: Int64;
  const TotalBytes: Int64 );
var
  BarText : String;
  CaptionText : String;
begin
  BarText := cnvFormatFileSize(CurrentBytes, uoscOperation) + '/' + cnvFormatFileSize(TotalBytes, uoscOperation);
  AProgressBar.SetProgress(CurrentBytes, TotalBytes, BarText );

  {$IFDEF LCLCOCOA}
  if TotalBytes > 0 then
    CaptionText := Format(rsComparingPercent, [CurrentBytes*100 div TotalBytes])
  else
    CaptionText := Format(rsComparingPercent, [0]);
  lblFileSizeProgress.Caption := CaptionText;
  {$ENDIF}
end;

function TfrmSyncDirsDlg.treeBuilderCheckRunning(const processMessages: Boolean): Boolean;
begin
  // At most every 50 ms: each call may process queued file-watcher events
  // and trigger panel reloads, which made a long compare O(n^2); and a status
  // bar update per directory is measurably expensive
  if processMessages and (GetTickCount64 - FLastMessagesTime >= 50) then
  begin
    FLastMessagesTime := GetTickCount64;
    StatusBar1.Panels[0].Text := Format(rsComparingPercent, [FScanShownPercent]);
    Application.ProcessMessages;
  end;
  Result:= NOT FCancel;
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
        FCancel:= True;
        Result:= uaAbort;
      end;
    else
      Result:= uaSkip;
  end;
end;

// Folders that could not be read and type conflicts without an action are
// left alone on both sides; a conflict with an action replaces the other
// side. Say so before synchronizing.
function TfrmSyncDirsDlg.confirmSkippedItems(const syncCount: TSyncDirsSyncCount): Boolean;

  function warn(const message: String; const count: Integer): Boolean;
  begin
    Result:= (count = 0) or
             (MessageDlg(Format(message, [count]), mtWarning, [mbYes, mbNo], 0, mbNo) = mrYes);
  end;

begin
  Result:= warn(rsSyncUnreadableWarning, FFilteredCount.unreadable) and
           warn(rsSyncTypeConflictWarning, syncCount.conflictKeepCount) and
           warn(rsSyncTypeConflictReplace, syncCount.conflictReplaceCount);
end;

procedure TfrmSyncDirsDlg.onTreeBuilderUpdateProgress(const percent: Integer);
begin
  FScanShownPercent := Max(FScanShownPercent, Min(99, percent));
end;

procedure TfrmSyncDirsDlg.SetPanelWatchers(AEnabled: Boolean);
var
  side: TDoubleSide;
begin
  // Resuming does a single reconciling reload of each panel
  for side := dsLeft to dsRight do
    if Assigned(FFileViews[side]) then
      FFileViews[side].SetWatcherEnabled(AEnabled);
end;

function TfrmSyncDirsDlg.commonCheckRunning: Boolean;
begin
  Result:= pnlProgress.Visible;
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

  // Trash or delete is asked along with the confirmation when the trash is
  // available, preset from the global setting; the choice holds for this
  // delete only
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
      EnableControls(False);
      pnlFileSizeProgress.Visible:= False;
      pnlFileCountProgress.Visible:= True;

      SetPanelWatchers(False);
      try
        commonService.delete(indexes, ALeft, ARight);
      finally
        SetPanelWatchers(True);
      end;
      self.FillFoundItemsDG;

      EnableControls(True);
    end;
  finally
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
        SetProgressBytes(pbFileSizeProgress, FCopyStatistics.DoneBytes, FCopyStatistics.TotalBytes);
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
        SetProgressFiles(pbFileCountProgress, FDeleteStatistics.DoneFiles, FDeleteStatistics.TotalFiles);
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
  Inc( FFileCountProgressDone );
  Application.ProcessMessages;
  if NOT Result then begin
    errMsg:= Format(rsMsgErrSetAttribute, [targetFile.FullPath]);
    askResult:= MessageDlg(errMsg, mtError, [mbIgnore, mbAbort], 0, mbAbort);
    Result:= (askResult = mrIgnore);
  end;
end;

function TfrmSyncDirsDlg.fileProcessorWithUIDeleteFile(
  const FileSource: IFileSource;
  const f: TFile ): Boolean;
var
  files: TFiles;
begin
  files := TFiles.Create(EmptyStr);
  files.OwnsObjects:= False;
  files.Add(f);
  Result:= fileProcessorWithUIDeleteFiles(FileSource, files);
  files.Free;
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
  end;
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
  end;
end;

// Answers given in one run must not leak into the next
procedure TfrmSyncDirsDlg.ResetDeleteOptions;
begin
  FDeleteSkipErrors := gSkipFileOpError;
  FDeleteReadOnlyOption := fsoogNone;
  FDeleteDirectlyOption := fsoogNone;
  FDeleteToTrash := gUseTrash;
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

procedure TfrmSyncDirsDlg.SetProgressBytes(AProgressBar: TKASProgressBar;
  CurrentBytes: Int64; TotalBytes: Int64);
var
  BarText : String;
  CaptionText : String;
begin
  {
    not all FileSources can provide precise statistical information,
    nor can they accurately calculate the generated size, for example, MultiArchive/7z.
    so this check has been added to prevent reporting an erroneous progress exceeding 100%
  }
  if CurrentBytes > TotalBytes then
    TotalBytes:= CurrentBytes + 1;

  BarText := cnvFormatFileSize(CurrentBytes, uoscOperation) + '/' + cnvFormatFileSize(TotalBytes, uoscOperation);
  AProgressBar.SetProgress(CurrentBytes, TotalBytes, BarText );

  {$IFDEF LCLCOCOA}
  if TotalBytes > 0 then
    CaptionText := rsOperCopying + ': ' + BarText + ' (' + FloatToStrF((CurrentBytes / TotalBytes) * 100, ffFixed, 0, 0) + '%)'
  else
    CaptionText := rsOperCopying;
  lblFileSizeProgress.Caption := CaptionText;
  {$ENDIF}
end;

procedure TfrmSyncDirsDlg.SetProgressFiles(AProgressBar: TKASProgressBar;
  CurrentFiles: Int64; TotalFiles: Int64);
var
  BarText : String;
  CaptionText : String;
begin
  {
    1. defensively prevent exceeding 100%
    2. for "Delete all empty directories"
  }
  if CurrentFiles > TotalFiles then
    TotalFiles:= CurrentFiles;

  BarText := IntToStrTS(CurrentFiles) + '/' + IntToStrTS(TotalFiles);
  AProgressBar.SetProgress(CurrentFiles, TotalFiles, BarText );

  {$IFDEF LCLCOCOA}
  if TotalFiles > 0 then
    CaptionText := rsOperDeleting + ': ' + BarText + ' (' + FloatToStrF((CurrentFiles / TotalFiles) * 100, ffFixed, 0, 0) + '%)'
  else
    CaptionText := rsOperDeleting;
  lblFileCountProgress.Caption := CaptionText;
  {$ENDIF}
end;

procedure TfrmSyncDirsDlg.updateFileCountProgress;
var
  progressBarText : String;
begin
  {
    1. defensively prevent exceeding 100%
    2. for "Delete all empty directories"
  }
  if FFileCountProgressDone > FFileCountProgressTotal then
    FFileCountProgressTotal:= FFileCountProgressDone;

  progressBarText := IntToStrTS(FFileCountProgressDone) + '/' + IntToStrTS(FFileCountProgressTotal);
  pbFileCountProgress.SetProgress(FFileCountProgressDone, FFileCountProgressTotal, progressBarText );

  {$IFDEF LCLCOCOA}
  if FFileCountProgressTotal > 0 then
    lblFileCountProgress.Caption := FFileCountProgressName + ': ' + progressBarText + ' (' + FloatToStrF((FFileCountProgressDone / FFileCountProgressTotal) * 100, ffFixed, 0, 0) + '%)'
  else
    lblFileCountProgress.Caption := FFileCountProgressName;
  {$ENDIF}
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
  FSortService := TSyncDirsSortService.Create;
  FFullTree := TTwoLevelTree.Create;
  FFilteredList := TFlatDirFileList.Create(FFullTree);
  FView := TSyncDirsView.Create(FFullTree, FFilteredList);
  FFileViews[dsLeft] := FileView1;
  FFileViews[dsRight] := FileView2;
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
  FScanning := False;
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

