unit fDeleteDlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  Buttons, Menus, StdCtrls, fButtonForm, uOperationsManager, uFileSource;

type
  TDeleteMode = (dmTrash, dmDelete, dmWipe);

  { TfrmDeleteDlg }

  TfrmDeleteDlg = class(TfrmButtonForm)
    rbTrash: TRadioButton;
    rbDelete: TRadioButton;
    rbWipe: TRadioButton;
    lblMessage: TLabel;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure rbModeChange(Sender: TObject);
  private
    FMessages: array[TDeleteMode] of String;
  public
    { public declarations }
  end;

function ShowDeleteDialog(TheOwner: TComponent; const Message: String; FileSource: IFileSource; out QueueId: TOperationsManagerQueueIdentifier): Boolean; overload;
function ShowDeleteDialog(TheOwner: TComponent; const TrashMessage, DeleteMessage, WipeMessage: String;
  FileSource: IFileSource; out QueueId: TOperationsManagerQueueIdentifier;
  ShowTrash, ShowWipe: Boolean; var DeleteMode: TDeleteMode): Boolean; overload;

implementation

uses
  LCLType, fMain;

function ShowDeleteDialog(TheOwner: TComponent; const Message: String; FileSource: IFileSource;
  out QueueId: TOperationsManagerQueueIdentifier): Boolean;
var
  Dlg: TfrmDeleteDlg;
  Mon: TMonitor;
begin
  Dlg := TfrmDeleteDlg.Create(TheOwner, FileSource);
  try
    Dlg.Caption := Application.Title;
    Dlg.lblMessage.Caption := Message;
    if Assigned(frmMain) and frmMain.HandleAllocated then
    begin
      Mon := frmMain.Monitor;
      Dlg.Left := frmMain.Left + (frmMain.Width  - Dlg.Width)  div 2;
      Dlg.Top  := frmMain.Top  + (frmMain.Height - Dlg.Height) div 2;
      if Dlg.Left < Mon.Left then Dlg.Left := Mon.Left;
      if Dlg.Top  < Mon.Top  then Dlg.Top  := Mon.Top;
      if Dlg.Left + Dlg.Width  > Mon.Left + Mon.Width  then Dlg.Left := Mon.Left + Mon.Width  - Dlg.Width;
      if Dlg.Top  + Dlg.Height > Mon.Top  + Mon.Height then Dlg.Top  := Mon.Top  + Mon.Height - Dlg.Height;
    end;
    Result := Dlg.ShowModal = mrOK;
    QueueId := Dlg.QueueIdentifier;
  finally
    Dlg.Free;
  end;
end;

function ShowDeleteDialog(TheOwner: TComponent; const TrashMessage, DeleteMessage, WipeMessage: String;
  FileSource: IFileSource; out QueueId: TOperationsManagerQueueIdentifier;
  ShowTrash, ShowWipe: Boolean; var DeleteMode: TDeleteMode): Boolean;
var
  Dlg: TfrmDeleteDlg;
  Mon: TMonitor;
begin
  Dlg := TfrmDeleteDlg.Create(TheOwner, FileSource);
  try
    Dlg.Caption := Application.Title;
    Dlg.FMessages[dmTrash]  := TrashMessage;
    Dlg.FMessages[dmDelete] := DeleteMessage;
    Dlg.FMessages[dmWipe]   := WipeMessage;
    Dlg.rbTrash.Visible  := ShowTrash;
    Dlg.rbDelete.Visible := True;
    Dlg.rbWipe.Visible   := ShowWipe;
    // Set initial selection; fall back to dmDelete if the preferred mode is unavailable
    case DeleteMode of
      dmTrash:  if ShowTrash then Dlg.rbTrash.Checked  := True else Dlg.rbDelete.Checked := True;
      dmWipe:   if ShowWipe  then Dlg.rbWipe.Checked   := True else Dlg.rbDelete.Checked := True;
      else           Dlg.rbDelete.Checked := True;
    end;
    Dlg.lblMessage.Caption := Dlg.FMessages[DeleteMode];
    if Assigned(frmMain) and frmMain.HandleAllocated then
    begin
      Mon := frmMain.Monitor;
      Dlg.Left := frmMain.Left + (frmMain.Width  - Dlg.Width)  div 2;
      Dlg.Top  := frmMain.Top  + (frmMain.Height - Dlg.Height) div 2;
      if Dlg.Left < Mon.Left then Dlg.Left := Mon.Left;
      if Dlg.Top  < Mon.Top  then Dlg.Top  := Mon.Top;
      if Dlg.Left + Dlg.Width  > Mon.Left + Mon.Width  then Dlg.Left := Mon.Left + Mon.Width  - Dlg.Width;
      if Dlg.Top  + Dlg.Height > Mon.Top  + Mon.Height then Dlg.Top  := Mon.Top  + Mon.Height - Dlg.Height;
    end;
    Result := Dlg.ShowModal = mrOK;
    if Result then
    begin
      if Dlg.rbTrash.Checked then DeleteMode := dmTrash
      else if Dlg.rbWipe.Checked then DeleteMode := dmWipe
      else DeleteMode := dmDelete;
    end;
    QueueId := Dlg.QueueIdentifier;
  finally
    Dlg.Free;
  end;
end;

{$R *.lfm}

{ TfrmDeleteDlg }

procedure TfrmDeleteDlg.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ssShift in Shift) then
  begin
    btnOK.Click;
    Key:= 0;
  end;
end;

procedure TfrmDeleteDlg.rbModeChange(Sender: TObject);
var
  Mode: TDeleteMode;
begin
  if rbTrash.Checked then Mode := dmTrash
  else if rbWipe.Checked then Mode := dmWipe
  else Mode := dmDelete;
  lblMessage.Caption := FMessages[Mode];
end;

end.

