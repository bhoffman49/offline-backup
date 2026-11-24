object FrameChecksums: TFrameChecksums
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
    object ButtonFolder: TButton
      Left = 8
      Height = 30
      Top = 12
      Width = 130
      Caption = 'Choose folder...'
      OnClick = ButtonFolderClick
      TabOrder = 0
    end
    object ButtonMake: TButton
      Left = 8
      Height = 30
      Top = 50
      Width = 130
      Caption = 'Make checksums'
      Enabled = False
      OnClick = ButtonMakeClick
      TabOrder = 1
    end
    object ButtonCancel: TButton
      Left = 8
      Height = 30
      Top = 88
      Width = 130
      Caption = 'Cancel'
      Enabled = False
      OnClick = ButtonCancelClick
      TabOrder = 2
    end
    object ButtonCheckList: TButton
      Left = 8
      Height = 30
      Top = 140
      Width = 130
      Caption = 'Check the list'
      Enabled = False
      OnClick = ButtonCheckListClick
      TabOrder = 3
    end
    object ButtonShow: TButton
      Left = 8
      Height = 30
      Top = 178
      Width = 130
      Caption = 'Show in Explorer'
      Enabled = False
      OnClick = ButtonShowClick
      TabOrder = 4
    end
  end
  object PanelMain: TPanel
    Left = 0
    Height = 517
    Top = 0
    Width = 618
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object LabelIntro: TLabel
      Left = 12
      Height = 32
      Top = 12
      Width = 594
      Anchors = [akTop, akLeft, akRight]
      AutoSize = False
      Caption =
        'Makes a list of every file'#39's checksum in a folder and saves it there, so the files can be checked ' +
        'later - under MD5 check, with ExactFile or md5sum, or with a small checksum program put next to them.'
      WordWrap = True
    end
    object LabelFolderCaption: TLabel
      Left = 12
      Height = 15
      Top = 54
      Width = 36
      Caption = 'Folder:'
    end
    object LabelFolder: TLabel
      Left = 64
      Height = 15
      Top = 54
      Width = 542
      Anchors = [akTop, akLeft, akRight]
      AutoSize = False
      Caption = 'none chosen yet - Choose folder...'
      EllipsisPosition = epPathEllipsis
      Font.Style = [fsBold]
      ParentFont = False
      ParentShowHint = False
      ShowHint = True
    end
    object CheckSub: TCheckBox
      Left = 12
      Height = 19
      Top = 76
      Width = 180
      Caption = 'Include subfolders'
      Checked = True
      Enabled = False
      State = cbChecked
      OnClick = CheckSubClick
      TabOrder = 0
    end
    object LabelCount: TLabel
      Left = 200
      Height = 15
      Top = 78
      Width = 406
      Alignment = taRightJustify
      Anchors = [akTop, akLeft, akRight]
      AutoSize = False
    end
    object ListFiles: TListView
      Left = 12
      Height = 164
      Top = 100
      Width = 594
      Anchors = [akTop, akLeft, akRight, akBottom]
      Columns = <
        item
          Caption = 'File'
          Width = 440
        end
        item
          Alignment = taRightJustify
          Caption = 'Size'
          Width = 110
        end>
      HideSelection = False
      MultiSelect = True
      OwnerData = True
      ReadOnly = True
      RowSelect = True
      TabOrder = 1
      ViewStyle = vsReport
      OnData = ListFilesData
      OnKeyDown = ListFilesKeyDown
      OnSelectItem = ListFilesSelectItem
    end
    object ButtonLeaveOut: TButton
      Left = 12
      Height = 26
      Top = 270
      Width = 160
      Anchors = [akLeft, akBottom]
      Caption = 'Leave out of the list'
      Enabled = False
      OnClick = ButtonLeaveOutClick
      TabOrder = 2
    end
    object LabelAlgo: TLabel
      Left = 12
      Height = 15
      Top = 314
      Width = 62
      Anchors = [akLeft, akBottom]
      Caption = 'Checksum:'
    end
    object ComboAlgo: TComboBox
      Left = 84
      Height = 23
      Top = 310
      Width = 120
      Anchors = [akLeft, akBottom]
      Style = csDropDownList
      DropDownCount = 16
      OnChange = ComboAlgoChange
      TabOrder = 3
    end
    object LabelFormat: TLabel
      Left = 222
      Height = 15
      Top = 314
      Width = 64
      Anchors = [akLeft, akBottom]
      Caption = 'List format:'
    end
    object ComboFormat: TComboBox
      Left = 296
      Height = 23
      Top = 310
      Width = 310
      Anchors = [akLeft, akRight, akBottom]
      Style = csDropDownList
      OnChange = ComboFormatChange
      TabOrder = 4
    end
    object CheckProgram: TCheckBox
      Left = 12
      Height = 19
      Top = 348
      Width = 594
      Anchors = [akLeft, akRight, akBottom]
      Caption = 'Also make a checksum program that checks these files on any PC (nothing to install)'
      OnClick = CheckProgramClick
      TabOrder = 5
    end
    object LabelName: TLabel
      Left = 31
      Height = 15
      Top = 382
      Width = 35
      Anchors = [akLeft, akBottom]
      Caption = 'Name:'
    end
    object EditName: TEdit
      Left = 84
      Height = 23
      Top = 378
      Width = 150
      Anchors = [akLeft, akBottom]
      OnChange = EditNameChange
      TabOrder = 6
    end
    object ButtonIcon: TButton
      Left = 248
      Height = 26
      Top = 376
      Width = 90
      Anchors = [akLeft, akBottom]
      Caption = 'Icon...'
      Enabled = False
      OnClick = ButtonIconClick
      TabOrder = 7
    end
    object ButtonDefaultIcon: TButton
      Left = 344
      Height = 26
      Top = 376
      Width = 100
      Anchors = [akLeft, akBottom]
      Caption = 'Built-in icon'
      Enabled = False
      OnClick = ButtonDefaultIconClick
      TabOrder = 8
    end
    object PaintIcon: TPaintBox
      Left = 456
      Height = 32
      Top = 373
      Width = 32
      Anchors = [akLeft, akBottom]
      Hint = 'The built-in icon'
      ParentShowHint = False
      ShowHint = True
      OnPaint = PaintIconPaint
    end
    object LabelOutput: TLabel
      Left = 12
      Height = 15
      Top = 418
      Width = 594
      Anchors = [akLeft, akRight, akBottom]
      AutoSize = False
      EllipsisPosition = epPathEllipsis
    end
    object ProgressBar: TProgressBar
      Left = 12
      Height = 18
      Top = 442
      Width = 594
      Anchors = [akLeft, akRight, akBottom]
      Max = 1000
      TabOrder = 9
    end
    object LabelStatus: TLabel
      Left = 12
      Height = 45
      Top = 466
      Width = 594
      Anchors = [akLeft, akRight, akBottom]
      AutoSize = False
      WordWrap = True
    end
  end
  object FolderDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Title = 'Choose the folder to make checksums for'
    Left = 360
    Top = 8
  end
  object IconDialog: TOpenDialog
    DefaultExt = 'ico'
    Filter = 'Icons (*.ico)|*.ico'
    Options = [ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Title = 'Choose the checksum program'#39's icon'
    Left = 400
    Top = 8
  end
  object Timer: TTimer
    Enabled = False
    Interval = 200
    OnTimer = TimerTimer
    Left = 440
    Top = 8
  end
end
