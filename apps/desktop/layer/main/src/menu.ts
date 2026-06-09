import type { MenuItem, MenuItemConstructorOptions } from "electron"
import { Menu } from "electron"

import { isMacOS } from "./env"
import { t } from "./lib/i18n"
import { revealLogFile } from "./logger"
import { WindowManager } from "./manager/window"

export const registerAppMenu = () => {
  const appDisplayName = "Folo"
  const menus: Array<MenuItemConstructorOptions | MenuItem> = [
    ...(isMacOS
      ? ([
          {
            label: appDisplayName,
            submenu: [
              { role: "services", label: t("menu.services") },
              { type: "separator" },
              { role: "hide", label: t("menu.hide", { name: appDisplayName }) },
              { role: "hideOthers", label: t("menu.hideOthers") },
              { type: "separator" },
              { role: "quit", label: t("menu.quit", { name: appDisplayName }) },
            ],
          },
        ] as MenuItemConstructorOptions[])
      : []),

    {
      role: "fileMenu",
      label: t("menu.file"),
      submenu: [
        { role: "close", label: t("menu.close") },
      ],
    },
    {
      label: t("menu.edit"),
      submenu: [
        { role: "undo", label: t("menu.undo") },
        { role: "redo", label: t("menu.redo") },
        { type: "separator" },
        { role: "cut", label: t("menu.cut") },
        { role: "copy", label: t("menu.copy") },
        { role: "paste", label: t("menu.paste") },
        { type: "separator" },
        ...((isMacOS
          ? [
              { role: "pasteAndMatchStyle", label: t("menu.pasteAndMatchStyle") },
              { role: "delete", label: t("menu.delete") },
              { role: "selectAll", label: t("menu.selectAll") },
            ]
          : [
              { role: "delete", label: t("menu.delete") },
              { type: "separator" },
              { role: "selectAll", label: t("menu.selectAll") },
            ]) as MenuItemConstructorOptions[]),
      ],
    },
    {
      role: "viewMenu",
      label: t("menu.view"),
      submenu: [
        { role: "reload", label: t("menu.reload") },
        { role: "forceReload", label: t("menu.forceReload") },
        { role: "toggleDevTools", label: t("menu.toggleDevTools") },
        { type: "separator" },

        { role: "togglefullscreen", label: t("menu.toggleFullScreen") },
      ],
    },
    {
      role: "windowMenu",
      label: t("menu.window"),
      submenu: [
        {
          role: "minimize",
          label: t("menu.minimize"),
        },
        {
          role: "zoom",
          label: t("menu.zoom"),
        },
        {
          type: "separator",
        },
        {
          role: "front",
          label: t("menu.front"),
        },
        {
          label: "Always on top",
          type: "checkbox",
          checked: WindowManager.getMainWindow()?.isAlwaysOnTop(),
          click: () => {
            const mainWindow = WindowManager.getMainWindow()
            if (!mainWindow) return
            mainWindow.setAlwaysOnTop(!mainWindow.isAlwaysOnTop())
            registerAppMenu()
          },
        },
      ],
    },
    {
      role: "help",
      label: t("menu.help"),
      submenu: [
        {
          label: t("menu.openLogFile"),
          click: async () => {
            await revealLogFile()
          },
        },
      ],
    },
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(menus))
}
