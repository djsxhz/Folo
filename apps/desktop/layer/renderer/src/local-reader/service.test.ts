import { FeedViewType } from "@follow/constants"
import { beforeEach, describe, expect, it, vi } from "vitest"

const mocks = vi.hoisted(() => {
  const storeEntries: Record<string, { id: string; feedId?: string | null; read: boolean }> = {}

  const localReader = {
    getTimeline: vi.fn(),
    setEntryRead: vi.fn(),
  }

  const getEntry = vi.fn((entryId: string) => storeEntries[entryId])

  return {
    storeEntries,
    localReader,
    entryActions: {
      markEntryReadStatusInSession: vi.fn(),
    },
    entryService: {
      patchMany: vi.fn(),
    },
    unreadActions: {
      updateById: vi.fn(),
    },
    getEntry,
    getSubscribedFeedIdAndInboxHandlesByView: vi.fn(() => ["feed-1"]),
  }
})

vi.mock("~/lib/client", () => ({
  ipcServices: {
    localReader: mocks.localReader,
  },
}))

vi.mock("@follow/database/services/entry", () => ({
  EntryService: {
    patchMany: mocks.entryService.patchMany,
  },
}))

vi.mock("@follow/store/collection/store", () => ({
  collectionActions: {
    reset: vi.fn(),
    upsertMany: vi.fn(),
  },
}))

vi.mock("@follow/store/entry/getter", () => ({
  getEntry: mocks.getEntry,
}))

vi.mock("@follow/store/entry/hooks", () => ({
  invalidateEntriesQuery: vi.fn(),
}))

vi.mock("@follow/store/entry/store", () => ({
  entryActions: {
    markEntryReadStatusInSession: mocks.entryActions.markEntryReadStatusInSession,
    reset: vi.fn(),
    upsertMany: vi.fn(),
  },
  useEntryStore: {
    getState: () => ({
      data: mocks.storeEntries,
    }),
  },
}))

vi.mock("@follow/store/feed/store", () => ({
  feedActions: {
    reset: vi.fn(),
    upsertMany: vi.fn(),
  },
  useFeedStore: {
    getState: () => ({
      feeds: {
        "feed-1": { id: "feed-1" },
      },
    }),
  },
}))

vi.mock("@follow/store/subscription/getter", () => ({
  getCategoryFeedIds: vi.fn(() => []),
  getSubscribedFeedIdAndInboxHandlesByView: mocks.getSubscribedFeedIdAndInboxHandlesByView,
}))

vi.mock("@follow/store/subscription/store", () => ({
  subscriptionActions: {
    reset: vi.fn(),
    upsertMany: vi.fn(),
  },
}))

vi.mock("@follow/store/unread/store", () => ({
  unreadActions: {
    reset: vi.fn(),
    upsertMany: vi.fn(),
    updateById: mocks.unreadActions.updateById,
  },
}))

import { markLocalBatchAsRead } from "./service"

describe("markLocalBatchAsRead", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    Object.keys(mocks.storeEntries).forEach((key) => {
      delete mocks.storeEntries[key]
    })
  })

  it("marks every local timeline entry even if one entry is missing from the renderer store", async () => {
    mocks.storeEntries["entry-1"] = {
      id: "entry-1",
      feedId: "feed-1",
      read: false,
    }

    mocks.localReader.getTimeline.mockResolvedValueOnce([
      {
        id: "entry-1",
        feedId: "feed-1",
        publishedAt: Date.now(),
        createdAt: Date.now(),
      },
      {
        id: "entry-2",
        feedId: "feed-1",
        publishedAt: Date.now(),
        createdAt: Date.now(),
      },
    ])

    await markLocalBatchAsRead({
      view: FeedViewType.Articles,
      filter: {
        feedIdList: ["feed-1"],
      },
      excludePrivate: false,
    })

    expect(mocks.localReader.getTimeline).toHaveBeenCalledWith({ feedId: "feed-1" })
    expect(mocks.localReader.setEntryRead).toHaveBeenNthCalledWith(1, {
      entryId: "entry-1",
      read: true,
    })
    expect(mocks.localReader.setEntryRead).toHaveBeenNthCalledWith(2, {
      entryId: "entry-2",
      read: true,
    })
    expect(mocks.entryService.patchMany).toHaveBeenCalledWith({
      entry: { read: true },
      entryIds: ["entry-1", "entry-2"],
    })
  })

  it("uses the subscribed feeds for the current view when marking all feeds as read", async () => {
    mocks.storeEntries["entry-1"] = {
      id: "entry-1",
      feedId: "feed-1",
      read: false,
    }
    mocks.localReader.getTimeline.mockResolvedValueOnce([
      {
        id: "entry-1",
        feedId: "feed-1",
        publishedAt: Date.now(),
        createdAt: Date.now(),
      },
    ])

    await markLocalBatchAsRead({
      view: FeedViewType.Articles,
      excludePrivate: true,
    })

    expect(mocks.getSubscribedFeedIdAndInboxHandlesByView).toHaveBeenCalledWith({
      view: FeedViewType.Articles,
      excludePrivate: true,
      excludeHidden: true,
    })
    expect(mocks.localReader.getTimeline).toHaveBeenCalledWith({ feedId: "feed-1" })
  })

  it("updates local entries sequentially to avoid concurrent IPC writes", async () => {
    let activeCalls = 0
    let maxConcurrentCalls = 0

    mocks.localReader.getTimeline.mockResolvedValueOnce([
      {
        id: "entry-1",
        feedId: "feed-1",
        publishedAt: Date.now(),
        createdAt: Date.now(),
      },
      {
        id: "entry-2",
        feedId: "feed-1",
        publishedAt: Date.now(),
        createdAt: Date.now(),
      },
    ])

    mocks.localReader.setEntryRead.mockImplementation(async () => {
      activeCalls += 1
      maxConcurrentCalls = Math.max(maxConcurrentCalls, activeCalls)
      await new Promise((resolve) => setTimeout(resolve, 0))
      activeCalls -= 1
    })

    await markLocalBatchAsRead({
      view: FeedViewType.Articles,
      filter: {
        feedIdList: ["feed-1"],
      },
      excludePrivate: false,
    })

    expect(maxConcurrentCalls).toBe(1)
  })
})
