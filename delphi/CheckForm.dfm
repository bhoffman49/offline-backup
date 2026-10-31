object FormCheck: TFormCheck
  Left = 420
  Height = 560
  Top = 110
  Width = 720
  Caption = 'Offline Backup - MD5 check'
  ClientHeight = 560
  ClientWidth = 720
  Constraints.MinHeight = 440
  Constraints.MinWidth = 600
  Position = poOwnerFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object LabelFile: TLabel
    Left = 12
    Height = 15
    Top = 12
    Width = 696
    Anchors = [akTop, akLeft, akRight]
    AutoSize = False
    Caption = ''
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LabelResult: TLabel
    Left = 12
    Height = 15
    Top = 34
    Width = 696
    Anchors = [akTop, akLeft, akRight]
    AutoSize = False
    Caption = ''
    Font.Style = [fsBold]
    ParentFont = False
  end
  object ListSummary: TListView
    Left = 12
    Height = 150
    Top = 60
    Width = 696
    Anchors = [akTop, akLeft, akRight]
    Columns = <
      item
        Caption = 'Files'
        Width = 300
      end
      item
        Alignment = taRightJustify
        Caption = 'Count'
        Width = 110
      end
      item
        Alignment = taRightJustify
        Caption = 'Size'
        Width = 110
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnSelectItem = ListSummarySelectItem
  end
  object LabelFiles: TLabel
    Left = 12
    Height = 15
    Top = 220
    Width = 400
    Caption = ''
    Font.Style = [fsBold]
    ParentFont = False
  end
  object ListFiles: TListView
    Left = 12
    Height = 280
    Top = 240
    Width = 696
    Anchors = [akTop, akLeft, akRight, akBottom]
    Columns = <
      item
        Caption = 'Result'
        Width = 100
      end
      item
        Caption = 'File'
        Width = 470
      end
      item
        Alignment = taRightJustify
        Caption = 'Size'
        Width = 90
      end>
    OwnerData = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 1
    ViewStyle = vsReport
    OnData = ListFilesData
  end
  object ButtonClose: TButton
    Left = 624
    Height = 28
    Top = 526
    Width = 84
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Close'
    Default = True
    ModalResult = 2
    TabOrder = 2
  end
end
