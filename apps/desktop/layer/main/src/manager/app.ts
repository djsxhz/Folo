import { APP_PROTOCOL, DEV, LEGACY_APP_PROTOCOL } from "@follow/shared/constants"
import { app, nativeTheme, shell } from "electron"
import contextMenu from "electron-context-menu"
import path from "pathe"

import { getIconPath } from "../helper"
import { initializeIpcServices } from "../ipc"
import { checkAndCleanCodeCache, clearCacheCronJob } from "../lib/cleaner"
import { t } from "../lib/i18n"
import { store } from "../lib/store"
import { initializeLocalReaderEngine } from "../local-reader/engine"
import { registerAppMenu } from "../menu"
import { LifecycleManager } from "./lifecycle"

class AppManagerStatic {
  private static instance: AppManagerStatic

  public static getInstance(): AppManagerStatic {
    if (!AppManagerStatic.instance) {
      AppManagerStatic.instance = new AppManagerStatic()
    }
    return AppManagerStatic.instance
  }

  public init() {
    initializeIpcServices()
    LifecycleManager.onReady(this.onReady.bind(this))
  }

  private onReady() {
    this.registerProtocols()
    this.setupAppVisuals()
    this.setupSystemConfigs()
    this.runCronJobs()
    this.registerMenuAndContextMenu()

    void initializeLocalReaderEngine()
  }

  private registerProtocols() {
    const protocols = [LEGACY_APP_PROTOCOL, APP_PROTOCOL]

    for (const protocolName of protocols) {
      if (process.defaultApp) {
        if (process.argv.length >= 2) {
          app.setAsDefaultProtocolClient(protocolName, process.execPath, [
            path.resolve(process.argv[1]!),
          ])
        }
      } else {
        app.setAsDefaultProtocolClient(protocolName)
      }
    }
  }

  private setupAppVisuals() {
    if (app.dock) {
      app.dock.setIcon(getIconPath())
    }
  }

  private setupSystemConfigs() {
    const appearance = store.get("appearance")
    if (appearance && ["light", "dark", "system"].includes(appearance)) {
      nativeTheme.themeSource = appearance
    }
  }

  private runCronJobs() {
    clearCacheCronJob()
    checkAndCleanCodeCache()
  }

  private contextMenuDisposer?: () => void
  public registerMenuAndContextMenu() {
    registerAppMenu()
    this.registerContextMenu()
  }

  public registerContextMenu() {
    if (this.contextMenuDisposer) {
      this.contextMenuDisposer()
    }

    this.contextMenuDisposer = contextMenu({
      showSaveImageAs: true,
      showCopyLink: true,
      showCopyImageAddress: true,
      showCopyImage: true,
      showInspectElement: DEV,
      showSelectAll: true,
      showCopyVideoAddress: true,
      showSaveVideoAs: true,

      labels: {
        saveImageAs: t("contextMenu.saveImageAs"),
        copyLink: t("contextMenu.copyLink"),
        copyImageAddress: t("contextMenu.copyImageAddress"),
        copyImage: t("contextMenu.copyImage"),
        copyVideoAddress: t("contextMenu.copyVideoAddress"),
        saveVideoAs: t("contextMenu.saveVideoAs"),
        inspect: t("contextMenu.inspect"),
        copy: t("contextMenu.copy"),
        cut: t("contextMenu.cut"),
        paste: t("contextMenu.paste"),
        saveImage: t("contextMenu.saveImage"),
        saveVideo: t("contextMenu.saveVideo"),
        selectAll: t("contextMenu.selectAll"),
        services: t("contextMenu.services"),
        searchWithGoogle: t("contextMenu.searchWithGoogle"),
        learnSpelling: t("contextMenu.learnSpelling"),
        lookUpSelection: t("contextMenu.lookUpSelection"),
        saveLinkAs: t("contextMenu.saveLinkAs"),
      },

      prepend: (_defaultActions, params) => {
        return [
          {
            label: t("contextMenu.openImageInBrowser"),
            visible: params.mediaType === "image",
            click: () => {
              shell.openExternal(params.srcURL)
            },
          },
          {
            label: t("contextMenu.openLinkInBrowser"),
            visible: params.linkURL !== "",
            click: () => {
              shell.openExternal(params.linkURL)
            },
          },
          {
            role: "undo",
            label: t("menu.undo"),
            accelerator: "CmdOrCtrl+Z",
            visible: params.isEditable,
          },
          {
            role: "redo",
            label: t("menu.redo"),
            accelerator: "CmdOrCtrl+Shift+Z",
            visible: params.isEditable,
          },
        ]
      },
    })
  }
}

export const AppManager = AppManagerStatic.getInstance()
