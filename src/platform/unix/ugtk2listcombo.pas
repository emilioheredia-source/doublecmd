{
  A read-only drop-down list (csDropDownList) opens under GTK2 as a menu
  over the pointer, and GTK takes a button release that comes more than
  about half a second after the press as the choice of the item under the
  pointer: a slow click, or a tap on a touchpad or a touch screen, opens the
  list and closes it again at once. The list style that editable combo boxes
  use opens below the box and waits for a click. This gives one combo box
  that style.
}

unit uGtk2ListCombo;

{$mode objfpc}{$H+}

interface

uses
  StdCtrls;

procedure ShowDropDownAsList(const ACombo: TCustomComboBox);

implementation

uses
  Gtk2, Gtk2Def, Gtk2Proc;

const
  WIDGET_NAME = 'dcListCombo';

var
  StyleAdded: Boolean = False;

procedure ShowDropDownAsList(const ACombo: TCustomComboBox);
var
  Info: PWidgetInfo;
begin
  Info := GetWidgetInfo({%H-}Pointer(ACombo.Handle));
  if (Info = nil) or (Info^.CoreWidget = nil) then
    Exit;
  if NOT StyleAdded then
  begin
    gtk_rc_parse_string(
      'style "' + WIDGET_NAME + '" { GtkComboBox::appears-as-list = 1 }' + LineEnding +
      'widget "*' + WIDGET_NAME + '" style "' + WIDGET_NAME + '"');
    StyleAdded := True;
  end;
  gtk_widget_set_name(Info^.CoreWidget, WIDGET_NAME);
  gtk_widget_reset_rc_styles(Info^.CoreWidget);
end;

end.
