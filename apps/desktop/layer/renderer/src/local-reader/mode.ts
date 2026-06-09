export const LOCAL_READER_MODE =
  typeof window !== "undefined" && Boolean(window.electron?.ipcRenderer)
