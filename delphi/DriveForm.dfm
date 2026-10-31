object FormDrive: TFormDrive
  Left = 440
  Height = 640
  Top = 90
  Width = 680
  Caption = 'Offline Backup - Drives'
  ClientHeight = 640
  ClientWidth = 680
  Constraints.MinHeight = 560
  Constraints.MinWidth = 600
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  PixelsPerInch = 96
  TextHeight = 15
  object LabelDrive: TLabel
    Left = 12
    Height = 15
    Top = 16
    Width = 40
    Caption = 'Drive:'
  end
  object ComboDrives: TComboBox
    Left = 60
    Height = 23
    Top = 12
    Width = 200
    Style = csDropDownList
    OnChange = ComboDrivesChange
    TabOrder = 0
  end
  object LabelState: TLabel
    Left = 12
    Height = 15
    Top = 46
    Width = 656
    Anchors = [akTop, akLeft, akRight]
    AutoSize = False
    Caption = ''
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LabelDescription: TLabel
    Left = 12
    Height = 15
    Top = 74
    Width = 300
    Caption = 'What this drive is for:'
  end
  object EditDescription: TEdit
    Left = 12
    Height = 23
    Top = 94
    Width = 506
    Anchors = [akTop, akLeft, akRight]
    MaxLength = 200
    TabOrder = 1
  end
  object ButtonApply: TButton
    Left = 526
    Height = 26
    Top = 92
    Width = 142
    Anchors = [akTop, akRight]
    Caption = 'Set up this drive'
    OnClick = ButtonApplyClick
    TabOrder = 2
  end
  object GroupFolders: TGroupBox
    Left = 12
    Height = 232
    Top = 130
    Width = 656
    Anchors = [akTop, akLeft, akRight]
    Caption = ' Folders this drive backs up '
    TabOrder = 3
    object ListFolders: TListView
      Left = 12
      Height = 140
      Top = 22
      Width = 632
      Anchors = [akTop, akLeft, akRight]
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
          Caption = 'On the drive'
          Width = 270
        end>
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
      OnDblClick = ButtonEditFolderClick
      OnSelectItem = ListFoldersSelectItem
    end
    object ButtonAddFolder: TButton
      Left = 12
      Height = 26
      Top = 168
      Width = 110
      Caption = 'Add folder...'
      OnClick = ButtonAddFolderClick
      TabOrder = 1
    end
    object ButtonEditFolder: TButton
      Left = 128
      Height = 26
      Top = 168
      Width = 90
      Caption = 'Edit...'
      OnClick = ButtonEditFolderClick
      TabOrder = 2
    end
    object ButtonRemoveFolder: TButton
      Left = 224
      Height = 26
      Top = 168
      Width = 90
      Caption = 'Remove'
      OnClick = ButtonRemoveFolderClick
      TabOrder = 3
    end
    object ButtonStarting: TButton
      Left = 474
      Height = 26
      Top = 168
      Width = 170
      Anchors = [akTop, akRight]
      Caption = 'Add starting folders'
      OnClick = ButtonStartingClick
      TabOrder = 4
    end
    object LabelFolderNote: TLabel
      Left = 12
      Height = 15
      Top = 204
      Width = 632
      Anchors = [akTop, akLeft, akRight]
      AutoSize = False
      Caption = ''
    end
  end
  object LabelHistory: TLabel
    Left = 12
    Height = 15
    Top = 372
    Width = 400
    Caption = 'Copies to this drive, newest first:'
  end
  object ListHistory: TListView
    Left = 12
    Height = 216
    Top = 392
    Width = 656
    Anchors = [akTop, akLeft, akRight, akBottom]
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
        Width = 290
      end
      item
        Caption = 'PC'
        Width = 80
      end>
    ReadOnly = True
    RowSelect = True
    TabOrder = 4
    ViewStyle = vsReport
  end
  object ButtonVerify: TButton
    Left = 12
    Height = 28
    Top = 610
    Width = 140
    Anchors = [akLeft, akBottom]
    Caption = 'Verify drive...'
    OnClick = ButtonVerifyClick
    TabOrder = 6
  end
  object ButtonClose: TButton
    Left = 584
    Height = 28
    Top = 610
    Width = 84
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Close'
    ModalResult = 2
    TabOrder = 5
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
