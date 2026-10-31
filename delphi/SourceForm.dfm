object FormSource: TFormSource
  Left = 450
  Height = 250
  Top = 250
  Width = 560
  BorderStyle = bsDialog
  Caption = 'Backup folder'
  ClientHeight = 250
  ClientWidth = 560
  Position = poOwnerFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object LabelPath: TLabel
    Left = 12
    Height = 15
    Top = 12
    Width = 200
    Caption = 'Folder to back up:'
  end
  object EditPath: TEdit
    Left = 12
    Height = 23
    Top = 32
    Width = 440
    OnChange = EditChange
    TabOrder = 0
  end
  object ButtonBrowse: TButton
    Left = 460
    Height = 25
    Top = 31
    Width = 88
    Caption = 'Browse...'
    OnClick = ButtonBrowseClick
    TabOrder = 1
  end
  object LabelName: TLabel
    Left = 12
    Height = 15
    Top = 68
    Width = 300
    Caption = 'Folder name on the OFFLINE drive:'
  end
  object EditName: TEdit
    Left = 12
    Height = 23
    Top = 88
    Width = 240
    OnChange = EditChange
    TabOrder = 2
  end
  object LabelLands: TLabel
    Left = 12
    Height = 15
    Top = 122
    Width = 536
    AutoSize = False
    Caption = 'Goes to: -'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LabelNote: TLabel
    Left = 12
    Height = 48
    Top = 146
    Width = 536
    AutoSize = False
    Caption =
      'Changing the folder or its name starts a new copy at the next run. On a drive, the old copy is ' +
      'then moved to _versions like a removed folder. A name that is already taken on the same drive ' +
      'letter gets a number, like MUSIC (2).'
    WordWrap = True
  end
  object ButtonOK: TButton
    Left = 372
    Height = 28
    Top = 210
    Width = 84
    Caption = 'OK'
    Default = True
    OnClick = ButtonOKClick
    TabOrder = 3
  end
  object ButtonCancel: TButton
    Left = 464
    Height = 28
    Top = 210
    Width = 84
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 4
  end
  object FolderDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Title = 'Choose a folder to back up'
    Left = 300
    Top = 80
  end
end
