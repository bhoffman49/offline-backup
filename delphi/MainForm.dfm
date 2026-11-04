object FormMain: TFormMain
  Left = 400
  Height = 540
  Top = 200
  Width = 860
  Caption = 'Offline Backup'
  ClientHeight = 540
  ClientWidth = 860
  Constraints.MinHeight = 420
  Constraints.MinWidth = 680
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object StatusBar: TStatusBar
    Left = 0
    Height = 23
    Top = 517
    Width = 860
    Panels = <
      item
        Width = 600
      end
      item
        Width = 200
      end>
  end
  object PanelBackup: TPanel
    Left = 0
    Height = 517
    Top = 0
    Width = 860
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object PanelBackupActions: TPanel
      Left = 710
      Height = 517
      Top = 0
      Width = 150
      Align = alRight
      BevelOuter = bvNone
      TabOrder = 1
      object ButtonStart: TButton
        Left = 8
        Height = 56
        Top = 34
        Width = 130
        Caption = 'Start copy'
        Enabled = False
        Font.Height = -15
        Font.Style = [fsBold]
        ParentFont = False
        OnClick = ButtonStartClick
        TabOrder = 0
      end
      object ButtonCancel: TButton
        Left = 8
        Height = 30
        Top = 98
        Width = 130
        Caption = 'Cancel'
        Enabled = False
        OnClick = ButtonCancelClick
        TabOrder = 1
      end
      object ButtonDismount: TButton
        Left = 8
        Height = 30
        Top = 136
        Width = 130
        Caption = 'Dismount'
        Visible = False
        OnClick = ButtonDismountClick
        TabOrder = 2
      end
    end
    object PageBackup: TPageControl
      AlignWithMargins = True
      Left = 8
      Height = 501
      Top = 8
      Width = 702
      Margins.Left = 8
      Margins.Top = 8
      Margins.Right = 0
      Margins.Bottom = 8
      ActivePage = TabDrivesIn
      Align = alClient
      TabOrder = 0
      object TabDrivesIn: TTabSheet
        Caption = 'Drives plugged in'
        object LabelDrives: TLabel
          AlignWithMargins = True
          Left = 6
          Height = 15
          Top = 8
          Width = 682
          Margins.Left = 6
          Margins.Top = 8
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alTop
          Caption = 'Looking for OFFLINE-x drives ...'
          WordWrap = True
        end
        object ListDrives: TListView
          AlignWithMargins = True
          Left = 6
          Height = 261
          Top = 29
          Width = 682
          Margins.Left = 6
          Margins.Top = 0
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alClient
          Columns = <
            item
              Caption = 'Drive'
              Width = 44
            end
            item
              Caption = 'Name'
              Width = 150
            end
            item
              Caption = 'What it is for'
              Width = 200
            end
            item
              AutoSize = True
              Caption = 'Last copy'
            end>
          ReadOnly = True
          RowSelect = True
          TabOrder = 0
          ViewStyle = vsReport
        end
        object SplitterProgress: TSplitter
          Cursor = crVSplit
          Left = 0
          Height = 5
          Top = 296
          Width = 694
          Align = alBottom
          MinSize = 80
        end
        object PanelProgress: TPanel
          Left = 0
          Height = 170
          Top = 301
          Width = 694
          Align = alBottom
          BevelOuter = bvNone
          TabOrder = 1
          object LabelStatus: TLabel
            Left = 12
            Height = 15
            Top = 8
            Width = 666
            Anchors = [akTop, akLeft, akRight]
            AutoSize = False
            Caption = 'Nothing running.'
            Font.Style = [fsBold]
            ParentFont = False
          end
          object LabelFile: TLabel
            Left = 12
            Height = 15
            Top = 30
            Width = 666
            Anchors = [akTop, akLeft, akRight]
            AutoSize = False
            Caption = ''
          end
          object LabelFileBar: TLabel
            Left = 12
            Height = 15
            Top = 54
            Width = 48
            AutoSize = False
            Caption = 'File:'
          end
          object ProgressFile: TProgressBar
            Left = 62
            Height = 18
            Top = 52
            Width = 476
            Anchors = [akTop, akLeft, akRight]
            TabOrder = 0
          end
          object LabelFilePct: TLabel
            Left = 546
            Height = 15
            Top = 54
            Width = 132
            Anchors = [akTop, akRight]
            AutoSize = False
            Caption = ''
          end
          object LabelTotalBar: TLabel
            Left = 12
            Height = 15
            Top = 80
            Width = 48
            AutoSize = False
            Caption = 'Total:'
          end
          object ProgressBar: TProgressBar
            Left = 62
            Height = 18
            Top = 78
            Width = 476
            Anchors = [akTop, akLeft, akRight]
            TabOrder = 1
          end
          object LabelTotalPct: TLabel
            Left = 546
            Height = 15
            Top = 80
            Width = 132
            Anchors = [akTop, akRight]
            AutoSize = False
            Caption = ''
          end
          object LabelEta: TLabel
            Left = 12
            Height = 15
            Top = 106
            Width = 666
            Anchors = [akTop, akLeft, akRight]
            AutoSize = False
            Caption = ''
          end
          object LabelCounts: TLabel
            Left = 12
            Height = 15
            Top = 126
            Width = 666
            Anchors = [akTop, akLeft, akRight]
            AutoSize = False
            Caption = ''
          end
          object LabelRate: TLabel
            Left = 12
            Height = 15
            Top = 146
            Width = 666
            Anchors = [akTop, akLeft, akRight]
            AutoSize = False
            Caption = ''
          end
        end
      end
      object TabLog: TTabSheet
        Caption = 'Log'
        object MemoLog: TMemo
          AlignWithMargins = True
          Left = 6
          Height = 459
          Top = 6
          Width = 682
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alClient
          ReadOnly = True
          ScrollBars = ssVertical
          TabOrder = 0
        end
      end
    end
  end
  object TrayIcon: TTrayIcon
    OnClick = TrayIconClick
    OnMouseUp = TrayIconMouseUp
    Left = 480
    Top = 40
  end
  object TrayMenu: TPopupMenu
    Left = 420
    Top = 40
    object MenuShow: TMenuItem
      Caption = 'Show'
      Default = True
      OnClick = MenuShowClick
    end
    object MenuStart: TMenuItem
      Caption = 'Start copy'
      Enabled = False
      OnClick = ButtonStartClick
    end
    object MenuSettings: TMenuItem
      Caption = 'Settings'
      OnClick = MenuSettingsClick
    end
    object MenuCheck: TMenuItem
      Caption = 'Check MD5 file...'
      OnClick = MenuCheckClick
    end
    object MenuDrives: TMenuItem
      Caption = 'Drives'
      OnClick = MenuDrivesClick
    end
    object MenuDismount: TMenuItem
      Caption = 'Dismount'
      Visible = False
      OnClick = ButtonDismountClick
    end
    object MenuSep: TMenuItem
      Caption = '-'
    end
    object MenuExit: TMenuItem
      Caption = 'Exit'
      OnClick = MenuExitClick
    end
  end
end
