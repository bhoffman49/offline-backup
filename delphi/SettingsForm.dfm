object FormSettings: TFormSettings
  Left = 420
  Height = 670
  Top = 90
  Width = 640
  Caption = 'Offline Backup - Settings'
  ClientHeight = 670
  ClientWidth = 640
  Constraints.MinHeight = 560
  Constraints.MinWidth = 560
  Position = poOwnerFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object LabelSources: TLabel
    Left = 12
    Height = 15
    Top = 12
    Width = 616
    Anchors = [akTop, akLeft, akRight]
    AutoSize = False
    Caption = 'Starting folders - Drives... offers the ticked ones when you set up a new drive:'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object ListSources: TListView
    Left = 12
    Height = 180
    Top = 32
    Width = 616
    Anchors = [akTop, akLeft, akRight, akBottom]
    Checkboxes = True
    Columns = <
      item
        Caption = 'Source'
        Width = 300
      end
      item
        Caption = ''
        Width = 32
      end
      item
        Caption = 'On the OFFLINE drive'
        Width = 260
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnDblClick = ButtonEditClick
    OnSelectItem = ListSourcesSelectItem
  end
  object ButtonAdd: TButton
    Left = 12
    Height = 26
    Top = 218
    Width = 90
    Anchors = [akLeft, akBottom]
    Caption = 'Add...'
    OnClick = ButtonAddClick
    TabOrder = 1
  end
  object ButtonEdit: TButton
    Left = 108
    Height = 26
    Top = 218
    Width = 90
    Anchors = [akLeft, akBottom]
    Caption = 'Edit...'
    OnClick = ButtonEditClick
    TabOrder = 2
  end
  object ButtonRemove: TButton
    Left = 204
    Height = 26
    Top = 218
    Width = 90
    Anchors = [akLeft, akBottom]
    Caption = 'Remove'
    OnClick = ButtonRemoveClick
    TabOrder = 3
  end
  object LabelExclude: TLabel
    Left = 12
    Height = 15
    Top = 258
    Width = 616
    Anchors = [akLeft, akRight, akBottom]
    AutoSize = False
    Caption = 'Folders never copied (a full path, or a name that is skipped everywhere). *.partial is always skipped.'
  end
  object ListExclude: TListBox
    Left = 12
    Height = 92
    Top = 278
    Width = 500
    Anchors = [akLeft, akRight, akBottom]
    ItemHeight = 15
    OnClick = ListExcludeClick
    TabOrder = 4
  end
  object ButtonExcludeFolder: TButton
    Left = 520
    Height = 26
    Top = 278
    Width = 108
    Anchors = [akRight, akBottom]
    Caption = 'Add folder...'
    OnClick = ButtonExcludeFolderClick
    TabOrder = 5
  end
  object ButtonExcludeName: TButton
    Left = 520
    Height = 26
    Top = 310
    Width = 108
    Anchors = [akRight, akBottom]
    Caption = 'Add name...'
    OnClick = ButtonExcludeNameClick
    TabOrder = 6
  end
  object ButtonExcludeRemove: TButton
    Left = 520
    Height = 26
    Top = 342
    Width = 108
    Anchors = [akRight, akBottom]
    Caption = 'Remove'
    OnClick = ButtonExcludeRemoveClick
    TabOrder = 7
  end
  object GroupLimits: TGroupBox
    Left = 12
    Height = 168
    Top = 382
    Width = 616
    Anchors = [akLeft, akRight, akBottom]
    Caption = ' Safety check and old versions '
    TabOrder = 8
    object LabelBrakePct: TLabel
      Left = 12
      Height = 15
      Top = 28
      Width = 470
      AutoSize = False
      Caption = 'Ask first when more than this % of a folder'#39's files would change or be deleted:'
    end
    object EditBrakePct: TEdit
      Left = 500
      Height = 23
      Top = 24
      Width = 70
      NumbersOnly = True
      TabOrder = 0
    end
    object LabelBrakeMin: TLabel
      Left = 12
      Height = 15
      Top = 62
      Width = 470
      AutoSize = False
      Caption = '... and at least this many files:'
    end
    object EditBrakeMin: TEdit
      Left = 500
      Height = 23
      Top = 58
      Width = 70
      NumbersOnly = True
      TabOrder = 1
    end
    object LabelKeepDays: TLabel
      Left = 12
      Height = 15
      Top = 96
      Width = 470
      AutoSize = False
      Caption = 'Keep old versions in _versions for this many days:'
    end
    object EditKeepDays: TEdit
      Left = 500
      Height = 23
      Top = 92
      Width = 70
      NumbersOnly = True
      TabOrder = 2
    end
    object LabelMaxFull: TLabel
      Left = 12
      Height = 15
      Top = 130
      Width = 470
      AutoSize = False
      Caption = 'Remove the oldest versions when the drive is fuller than this %:'
    end
    object EditMaxFull: TEdit
      Left = 500
      Height = 23
      Top = 126
      Width = 70
      NumbersOnly = True
      TabOrder = 3
    end
  end
  object CheckPreview: TCheckBox
    Left = 12
    Height = 19
    Top = 562
    Width = 616
    Anchors = [akLeft, akBottom]
    Caption = 'Show a preview of the changes before every copy (otherwise only when files would be deleted or moved)'
    TabOrder = 13
  end
  object LabelLogFile: TLabel
    Left = 12
    Height = 15
    Top = 598
    Width = 60
    Anchors = [akLeft, akBottom]
    Caption = 'Log file:'
  end
  object EditLogFile: TEdit
    Left = 76
    Height = 23
    Top = 594
    Width = 508
    Anchors = [akLeft, akRight, akBottom]
    TabOrder = 9
  end
  object ButtonLogFile: TButton
    Left = 590
    Height = 25
    Top = 593
    Width = 38
    Anchors = [akRight, akBottom]
    Caption = '...'
    OnClick = ButtonLogFileClick
    TabOrder = 10
  end
  object ButtonOK: TButton
    Left = 452
    Height = 28
    Top = 630
    Width = 84
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    Default = True
    OnClick = ButtonOKClick
    TabOrder = 11
  end
  object ButtonCancel: TButton
    Left = 544
    Height = 28
    Top = 630
    Width = 84
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 12
  end
  object FolderDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Title = 'Choose a folder'
    Left = 420
    Top = 216
  end
  object LogDialog: TSaveDialog
    DefaultExt = 'log'
    Filter = 'Log files (*.log)|*.log|All files (*.*)|*.*'
    Options = [ofHideReadOnly, ofEnableSizing]
    Title = 'Log file'
    Left = 480
    Top = 216
  end
end
