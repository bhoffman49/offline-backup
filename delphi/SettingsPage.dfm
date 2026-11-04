object FrameSettings: TFrameSettings
  Left = 0
  Height = 517
  Top = 0
  Width = 768
  TabOrder = 0
  object PanelActions: TPanel
    Left = 618
    Height = 517
    Top = 0
    Width = 150
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 1
    object ButtonSave: TButton
      Left = 8
      Height = 30
      Top = 34
      Width = 130
      Caption = 'Save'
      OnClick = ButtonSaveClick
      TabOrder = 0
    end
    object ButtonUndo: TButton
      Left = 8
      Height = 30
      Top = 72
      Width = 130
      Caption = 'Undo changes'
      OnClick = ButtonUndoClick
      TabOrder = 1
    end
  end
  object PageSettings: TPageControl
    AlignWithMargins = True
    Left = 8
    Height = 501
    Top = 8
    Width = 610
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 0
    Margins.Bottom = 8
    ActivePage = TabSources
    Align = alClient
    TabOrder = 0
    object TabSources: TTabSheet
      Caption = 'Starting folders'
      object LabelSources: TLabel
        AlignWithMargins = True
        Left = 12
        Height = 30
        Top = 12
        Width = 578
        Margins.Left = 12
        Margins.Top = 12
        Margins.Right = 12
        Margins.Bottom = 6
        Align = alTop
        AutoSize = False
        Caption =
          'Starting folders: when you set up a new drive under Drives, Add starting folders puts the ticked ones' +
          ' on its list. Each drive keeps its own list after that.'
        WordWrap = True
      end
      object PanelSourceButtons: TPanel
        Left = 0
        Height = 44
        Top = 427
        Width = 602
        Align = alBottom
        BevelOuter = bvNone
        TabOrder = 1
        object ButtonAdd: TButton
          Left = 12
          Height = 26
          Top = 8
          Width = 100
          Caption = 'Add...'
          OnClick = ButtonAddClick
          TabOrder = 0
        end
        object ButtonEdit: TButton
          Left = 118
          Height = 26
          Top = 8
          Width = 100
          Caption = 'Edit...'
          OnClick = ButtonEditClick
          TabOrder = 1
        end
        object ButtonRemove: TButton
          Left = 224
          Height = 26
          Top = 8
          Width = 100
          Caption = 'Remove'
          OnClick = ButtonRemoveClick
          TabOrder = 2
        end
      end
      object ListSources: TListView
        AlignWithMargins = True
        Left = 12
        Height = 379
        Top = 48
        Width = 578
        Margins.Left = 12
        Margins.Top = 0
        Margins.Right = 12
        Margins.Bottom = 0
        Align = alClient
        Checkboxes = True
        Columns = <
          item
            Caption = 'Source'
            Width = 260
          end
          item
            Caption = ''
            Width = 28
          end
          item
            Caption = 'On the OFFLINE drive'
            Width = 250
          end>
        HideSelection = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnDblClick = ButtonEditClick
        OnSelectItem = ListSourcesSelectItem
      end
    end
    object TabExclude: TTabSheet
      Caption = 'Excluded folders'
      object LabelExclude: TLabel
        AlignWithMargins = True
        Left = 12
        Height = 30
        Top = 12
        Width = 578
        Margins.Left = 12
        Margins.Top = 12
        Margins.Right = 12
        Margins.Bottom = 6
        Align = alTop
        AutoSize = False
        Caption =
          'Folders never copied: a full path, or a name that is skipped everywhere. *.partial files are always ' +
          'skipped.'
        WordWrap = True
      end
      object PanelExcludeButtons: TPanel
        Left = 0
        Height = 44
        Top = 427
        Width = 602
        Align = alBottom
        BevelOuter = bvNone
        TabOrder = 1
        object ButtonExcludeFolder: TButton
          Left = 12
          Height = 26
          Top = 8
          Width = 100
          Caption = 'Add folder...'
          OnClick = ButtonExcludeFolderClick
          TabOrder = 0
        end
        object ButtonExcludeName: TButton
          Left = 118
          Height = 26
          Top = 8
          Width = 100
          Caption = 'Add name...'
          OnClick = ButtonExcludeNameClick
          TabOrder = 1
        end
        object ButtonExcludeRemove: TButton
          Left = 224
          Height = 26
          Top = 8
          Width = 100
          Caption = 'Remove'
          OnClick = ButtonExcludeRemoveClick
          TabOrder = 2
        end
      end
      object ListExclude: TListBox
        AlignWithMargins = True
        Left = 12
        Height = 379
        Top = 48
        Width = 578
        Margins.Left = 12
        Margins.Top = 0
        Margins.Right = 12
        Margins.Bottom = 0
        Align = alClient
        ItemHeight = 15
        TabOrder = 0
        OnClick = ListExcludeClick
      end
    end
    object TabSafety: TTabSheet
      Caption = 'Safety and versions'
      object LabelBrakePct: TLabel
        Left = 12
        Height = 15
        Top = 18
        Width = 480
        AutoSize = False
        Caption = 'Ask first when more than this % of a folder'#39's files would change or be deleted:'
      end
      object EditBrakePct: TEdit
        Left = 500
        Height = 23
        Top = 14
        Width = 70
        NumbersOnly = True
        TabOrder = 0
      end
      object LabelBrakeMin: TLabel
        Left = 12
        Height = 15
        Top = 52
        Width = 480
        AutoSize = False
        Caption = '... and at least this many files:'
      end
      object EditBrakeMin: TEdit
        Left = 500
        Height = 23
        Top = 48
        Width = 70
        NumbersOnly = True
        TabOrder = 1
      end
      object LabelKeepDays: TLabel
        Left = 12
        Height = 15
        Top = 86
        Width = 480
        AutoSize = False
        Caption = 'Keep old versions in _versions for this many days:'
      end
      object EditKeepDays: TEdit
        Left = 500
        Height = 23
        Top = 82
        Width = 70
        NumbersOnly = True
        TabOrder = 2
      end
      object LabelMaxFull: TLabel
        Left = 12
        Height = 15
        Top = 120
        Width = 480
        AutoSize = False
        Caption = 'Remove the oldest versions when the drive is fuller than this %:'
      end
      object EditMaxFull: TEdit
        Left = 500
        Height = 23
        Top = 116
        Width = 70
        NumbersOnly = True
        TabOrder = 3
      end
      object CheckPreview: TCheckBox
        Left = 12
        Height = 19
        Top = 162
        Width = 570
        Anchors = [akTop, akLeft, akRight]
        Caption = 'Show a preview of the changes before every copy'
        TabOrder = 4
      end
      object LabelPreviewNote: TLabel
        Left = 31
        Height = 15
        Top = 184
        Width = 551
        Anchors = [akTop, akLeft, akRight]
        AutoSize = False
        Caption = 'Otherwise the preview only shows when files would be deleted or moved.'
      end
    end
    object TabEncryption: TTabSheet
      Caption = 'Encryption'
      object CheckDismount: TCheckBox
        Left = 12
        Height = 19
        Top = 16
        Width = 570
        Anchors = [akTop, akLeft, akRight]
        Caption = 'Dismount VeraCrypt drives after a copy that went well'
        TabOrder = 0
      end
      object LabelDismountNote: TLabel
        Left = 31
        Height = 15
        Top = 38
        Width = 551
        Anchors = [akTop, akLeft, akRight]
        AutoSize = False
        Caption = 'Then they can be unplugged straight away.'
      end
      object LabelVeraCrypt: TLabel
        Left = 12
        Height = 45
        Top = 70
        Width = 570
        Anchors = [akTop, akLeft, akRight]
        AutoSize = False
        Caption = ''
        WordWrap = True
      end
    end
    object TabLogFile: TTabSheet
      Caption = 'Log file'
      object LabelLogFile: TLabel
        Left = 12
        Height = 15
        Top = 14
        Width = 300
        Caption = 'Each copy is written to this log file:'
      end
      object EditLogFile: TEdit
        Left = 12
        Height = 23
        Top = 34
        Width = 538
        Anchors = [akTop, akLeft, akRight]
        TabOrder = 0
      end
      object ButtonLogFile: TButton
        Left = 556
        Height = 25
        Top = 33
        Width = 34
        Anchors = [akTop, akRight]
        Caption = '...'
        OnClick = ButtonLogFileClick
        TabOrder = 1
      end
      object LabelSettingsFile: TLabel
        Left = 12
        Height = 45
        Top = 76
        Width = 578
        Anchors = [akTop, akLeft, akRight]
        AutoSize = False
        Caption = ''
        WordWrap = True
      end
    end
  end
  object FolderDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Title = 'Choose a folder'
    Left = 360
    Top = 8
  end
  object LogDialog: TSaveDialog
    DefaultExt = 'log'
    Filter = 'Log files (*.log)|*.log|All files (*.*)|*.*'
    Options = [ofHideReadOnly, ofEnableSizing]
    Title = 'Log file'
    Left = 420
    Top = 8
  end
end
