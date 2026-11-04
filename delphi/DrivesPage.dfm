object FrameDrives: TFrameDrives
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
    TabOrder = 2
    object ButtonApply: TButton
      Left = 8
      Height = 30
      Top = 34
      Width = 130
      Caption = 'Save'
      OnClick = ButtonApplyClick
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
    object ButtonVerify: TButton
      Left = 8
      Height = 30
      Top = 120
      Width = 130
      Caption = 'Verify drive...'
      OnClick = ButtonVerifyClick
      TabOrder = 2
    end
    object ButtonPrepare: TButton
      Left = 8
      Height = 30
      Top = 158
      Width = 130
      Caption = 'Prepare a new drive...'
      Enabled = False
      TabOrder = 3
    end
  end
  object PanelTop: TPanel
    Left = 0
    Height = 64
    Top = 0
    Width = 618
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object LabelDrive: TLabel
      Left = 10
      Height = 15
      Top = 14
      Width = 40
      Caption = 'Drive:'
    end
    object ComboDrives: TComboBox
      Left = 56
      Height = 23
      Top = 10
      Width = 220
      Style = csDropDownList
      OnChange = ComboDrivesChange
      TabOrder = 0
    end
    object LabelState: TLabel
      Left = 10
      Height = 15
      Top = 42
      Width = 600
      Anchors = [akTop, akLeft, akRight]
      AutoSize = False
      Caption = ''
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object PageDrive: TPageControl
    AlignWithMargins = True
    Left = 8
    Height = 445
    Top = 64
    Width = 610
    Margins.Left = 8
    Margins.Top = 0
    Margins.Right = 0
    Margins.Bottom = 8
    ActivePage = TabFolders
    Align = alClient
    TabOrder = 1
    object TabFolders: TTabSheet
      Caption = 'Folders'
      object PanelDescription: TPanel
        Left = 0
        Height = 88
        Top = 0
        Width = 602
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        object LabelDescription: TLabel
          Left = 12
          Height = 15
          Top = 12
          Width = 300
          Caption = 'What this drive is for:'
        end
        object EditDescription: TEdit
          Left = 12
          Height = 23
          Top = 32
          Width = 578
          Anchors = [akTop, akLeft, akRight]
          MaxLength = 200
          TabOrder = 0
        end
        object LabelFolders: TLabel
          Left = 12
          Height = 15
          Top = 68
          Width = 300
          Caption = 'Folders this drive backs up:'
        end
      end
      object PanelFolderButtons: TPanel
        Left = 0
        Height = 68
        Top = 349
        Width = 602
        Align = alBottom
        BevelOuter = bvNone
        TabOrder = 2
        object ButtonAddFolder: TButton
          Left = 12
          Height = 26
          Top = 8
          Width = 110
          Caption = 'Add folder...'
          OnClick = ButtonAddFolderClick
          TabOrder = 0
        end
        object ButtonEditFolder: TButton
          Left = 128
          Height = 26
          Top = 8
          Width = 90
          Caption = 'Edit...'
          OnClick = ButtonEditFolderClick
          TabOrder = 1
        end
        object ButtonRemoveFolder: TButton
          Left = 224
          Height = 26
          Top = 8
          Width = 90
          Caption = 'Remove'
          OnClick = ButtonRemoveFolderClick
          TabOrder = 2
        end
        object ButtonStarting: TButton
          Left = 420
          Height = 26
          Top = 8
          Width = 170
          Anchors = [akTop, akRight]
          Caption = 'Add starting folders'
          OnClick = ButtonStartingClick
          TabOrder = 3
        end
        object LabelFolderNote: TLabel
          Left = 12
          Height = 15
          Top = 44
          Width = 578
          Anchors = [akTop, akLeft, akRight]
          AutoSize = False
          Caption = ''
        end
      end
      object ListFolders: TListView
        AlignWithMargins = True
        Left = 12
        Height = 261
        Top = 88
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
            Caption = 'On the drive'
            Width = 250
          end>
        HideSelection = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 1
        ViewStyle = vsReport
        OnDblClick = ButtonEditFolderClick
        OnSelectItem = ListFoldersSelectItem
      end
    end
    object TabHistory: TTabSheet
      Caption = 'History'
      object LabelHistory: TLabel
        AlignWithMargins = True
        Left = 12
        Height = 15
        Top = 12
        Width = 578
        Margins.Left = 12
        Margins.Top = 12
        Margins.Right = 12
        Margins.Bottom = 6
        Align = alTop
        Caption = 'Copies to this drive, newest first:'
      end
      object ListHistory: TListView
        AlignWithMargins = True
        Left = 12
        Height = 370
        Top = 33
        Width = 578
        Margins.Left = 12
        Margins.Top = 0
        Margins.Right = 12
        Margins.Bottom = 12
        Align = alClient
        Columns = <
          item
            Caption = 'When'
            Width = 115
          end
          item
            Caption = 'Result'
            Width = 75
          end
          item
            Caption = 'Copied'
            Width = 80
          end
          item
            Caption = 'Folders'
            Width = 220
          end
          item
            Caption = 'PC'
            Width = 80
          end>
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
      end
    end
  end
  object FolderDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Title = 'Choose a folder for this drive to back up'
    Left = 360
    Top = 8
  end
end
