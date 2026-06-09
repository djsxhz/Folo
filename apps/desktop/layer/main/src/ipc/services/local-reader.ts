import type { FeedViewType } from "@follow/constants"
import type { IpcContext } from "electron-ipc-decorator"
import { IpcMethod, IpcService } from "electron-ipc-decorator"

import {
  addFeed,
  deleteFeed,
  getCategories,
  getEntry,
  getFeeds,
  getSettings,
  getTimeline,
  initializeLocalReaderEngine,
  markAllAsRead,
  refreshAllFeeds,
  refreshFeed,
  setEntryRead,
  setEntryStarred,
  updateFeed,
  updateSettings,
} from "../../local-reader/engine"

export class LocalReaderService extends IpcService {
  static override readonly groupName = "localReader"

  @IpcMethod()
  async initialize(_context: IpcContext) {
    await initializeLocalReaderEngine()
    return { success: true }
  }

  @IpcMethod()
  async getFeeds(_context: IpcContext) {
    return getFeeds()
  }

  @IpcMethod()
  async getCategories(_context: IpcContext) {
    return getCategories()
  }

  @IpcMethod()
  async getSettings(_context: IpcContext) {
    return getSettings()
  }

  @IpcMethod()
  async updateSettings(
    _context: IpcContext,
    input: {
      refreshIntervalMinutes?: number
    },
  ) {
    return updateSettings(input)
  }

  @IpcMethod()
  async getTimeline(
    _context: IpcContext,
    input?: {
      feedId?: string
      category?: string
      starredOnly?: boolean
      videosOnly?: boolean
      search?: string
    },
  ) {
    return getTimeline(input)
  }

  @IpcMethod()
  async getEntry(_context: IpcContext, input: { entryId: string }) {
    return getEntry(input.entryId)
  }

  @IpcMethod()
  async addFeed(
    _context: IpcContext,
    input: {
      url: string
      category?: string | null
      title?: string | null
      view?: FeedViewType
    },
  ) {
    return addFeed(input)
  }

  @IpcMethod()
  async updateFeed(
    _context: IpcContext,
    input: {
      feedId: string
      title?: string | null
      category?: string | null
      view?: FeedViewType
    },
  ) {
    return updateFeed(input)
  }

  @IpcMethod()
  async deleteFeed(_context: IpcContext, input: { feedId: string }) {
    return deleteFeed(input.feedId)
  }

  @IpcMethod()
  async refreshFeed(_context: IpcContext, input: { feedId: string }) {
    return refreshFeed(input.feedId)
  }

  @IpcMethod()
  async refreshAll(_context: IpcContext) {
    return refreshAllFeeds()
  }

  @IpcMethod()
  async setEntryRead(
    _context: IpcContext,
    input: {
      entryId: string
      read: boolean
    },
  ) {
    return setEntryRead(input)
  }

  @IpcMethod()
  async setEntryStarred(
    _context: IpcContext,
    input: {
      entryId: string
      starred: boolean
    },
  ) {
    return setEntryStarred(input)
  }

  @IpcMethod()
  async markAllAsRead(
    _context: IpcContext,
    input?: {
      feedId?: string
      category?: string
      starredOnly?: boolean
      videosOnly?: boolean
      search?: string
    },
  ) {
    return markAllAsRead(input)
  }
}
