import { FeedViewType } from "@follow/constants"
import type {
  CollectionSchema,
  EntrySchema,
  FeedSchema,
  UnreadSchema,
} from "@follow/database/schemas/types"
import { EntryService } from "@follow/database/services/entry"
import { collectionActions } from "@follow/store/collection/store"
import { getEntry } from "@follow/store/entry/getter"
import { invalidateEntriesQuery } from "@follow/store/entry/hooks"
import { entryActions, useEntryStore } from "@follow/store/entry/store"
import { feedActions, useFeedStore } from "@follow/store/feed/store"
import {
  getCategoryFeedIds,
  getSubscribedFeedIdAndInboxHandlesByView,
} from "@follow/store/subscription/getter"
import { subscriptionActions } from "@follow/store/subscription/store"
import type { SubscriptionModel } from "@follow/store/subscription/types"
import { unreadActions } from "@follow/store/unread/store"

import { ipcServices } from "~/lib/client"

import { LOCAL_READER_MODE } from "./mode"

type LocalReaderIpc = NonNullable<typeof ipcServices>["localReader"]
type LocalFeed = Awaited<ReturnType<LocalReaderIpc["getFeeds"]>>[number]
type LocalEntry = Awaited<ReturnType<LocalReaderIpc["getTimeline"]>>[number]
type MarkAllFilter =
  | {
      startTime: number
      endTime: number
    }
  | {
      insertedBefore: number
    }

let syncPromise: Promise<void> | null = null
let localReaderMutationPromise: Promise<void> = Promise.resolve()

const LOCAL_READER_USER_ID = "local-reader"

const queueLocalReaderMutation = async <T>(operation: () => Promise<T>) => {
  const nextTask = localReaderMutationPromise.then(operation, operation)
  localReaderMutationPromise = nextTask.then(
    () => undefined,
    () => undefined,
  )
  return nextTask
}

const waitForLocalReaderMutations = async () => {
  await localReaderMutationPromise
}

const getLocalReaderIpc = () => {
  const localReader = ipcServices?.localReader
  if (!localReader) {
    throw new Error("Local reader IPC is unavailable")
  }

  return localReader
}

const escapeHtml = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")

const inferFeedView = (feed: LocalFeed, entries: LocalEntry[]) => {
  if (typeof feed.view === "number") {
    return feed.view
  }

  const videoCount = entries.filter((entry) => entry.kind === "video").length
  return videoCount > 0 && videoCount >= Math.ceil(entries.length / 2)
    ? FeedViewType.Videos
    : FeedViewType.Articles
}

const buildFeedSchema = (feed: LocalFeed, entries: LocalEntry[]): FeedSchema => ({
  id: feed.id,
  title: feed.title,
  url: feed.url,
  description: feed.description,
  image: feed.imageUrl,
  errorAt: null,
  siteUrl: feed.siteUrl,
  ownerUserId: LOCAL_READER_USER_ID,
  errorMessage: feed.lastError,
  subscriptionCount: 1,
  updatesPerWeek: null,
  latestEntryPublishedAt: entries[0] ? new Date(entries[0].publishedAt).toISOString() : null,
  tipUserIds: [],
  updatedAt: feed.lastFetchedAt ? new Date(feed.lastFetchedAt) : null,
})

const buildEntryContent = (entry: LocalEntry) => {
  if (entry.contentHtml) {
    return entry.contentHtml
  }

  if (entry.videoUrl) {
    return `<video controls src="${escapeHtml(entry.videoUrl)}"></video>`
  }

  if (entry.embedUrl) {
    return `<iframe src="${escapeHtml(entry.embedUrl)}" allowfullscreen></iframe>`
  }

  if (entry.url) {
    const safeUrl = escapeHtml(entry.url)
    return `<p><a href="${safeUrl}" target="_blank" rel="noreferrer">${safeUrl}</a></p>`
  }

  return null
}

const buildEntryAttachments = (entry: LocalEntry): EntrySchema["attachments"] => {
  const attachments = entry.attachments.map((attachment) => ({
    url: attachment.url,
    mime_type: attachment.mimeType ?? undefined,
  }))

  if (entry.videoUrl && !attachments.some((attachment) => attachment.url === entry.videoUrl)) {
    attachments.unshift({
      url: entry.videoUrl,
      mime_type: "video/mp4",
    })
  }

  return attachments.length > 0 ? attachments : null
}

const buildEntryMedia = (entry: LocalEntry): EntrySchema["media"] => {
  const attachmentThumbnailUrl =
    entry.attachments.find((attachment) => attachment.mimeType?.startsWith("image"))?.url ?? null
  const thumbnailUrl = entry.thumbnailUrl ?? attachmentThumbnailUrl

  if (entry.kind === "video") {
    if (thumbnailUrl) {
      return [
        {
          url: thumbnailUrl,
          type: "photo",
        },
      ]
    }

    if (entry.videoUrl) {
      return [
        {
          url: entry.videoUrl,
          type: "video",
        },
      ]
    }

    return null
  }

  if (!thumbnailUrl) {
    return null
  }

  return [
    {
      url: thumbnailUrl,
      type: "photo",
    },
  ]
}

const buildEntrySchema = (entry: LocalEntry, feed: LocalFeed): EntrySchema => ({
  id: entry.id,
  title: entry.title,
  url: entry.url,
  content: buildEntryContent(entry),
  readabilityContent: null,
  readabilityUpdatedAt: null,
  description: entry.excerpt,
  guid: entry.guid,
  author: entry.author,
  authorUrl: null,
  authorAvatar: feed.imageUrl,
  insertedAt: new Date(entry.createdAt),
  publishedAt: new Date(entry.publishedAt),
  media: buildEntryMedia(entry),
  categories: feed.category ? [feed.category] : null,
  attachments: buildEntryAttachments(entry),
  extra: null,
  language: "zh-CN",
  feedId: entry.feedId,
  inboxHandle: null,
  read: entry.read,
  sources: null,
  settings: null,
})

const buildSubscriptionModel = (feed: LocalFeed, entries: LocalEntry[]): SubscriptionModel => ({
  feedId: feed.id,
  listId: null,
  inboxId: null,
  userId: LOCAL_READER_USER_ID,
  view: inferFeedView(feed, entries),
  isPrivate: false,
  hideFromTimeline: false,
  title: feed.title,
  category: feed.category,
  createdAt: new Date(feed.createdAt).toISOString(),
  type: "feed",
})

const buildUnreadRows = (entries: EntrySchema[]): UnreadSchema[] => {
  const unreadCountByFeed = new Map<string, number>()

  for (const entry of entries) {
    if (!entry.feedId || entry.read) {
      continue
    }

    unreadCountByFeed.set(entry.feedId, (unreadCountByFeed.get(entry.feedId) ?? 0) + 1)
  }

  return Array.from(unreadCountByFeed.entries()).map(([id, count]) => ({
    id,
    count,
  }))
}

const buildCollectionsFromLocalEntries = (
  localEntries: LocalEntry[],
  subscriptions: SubscriptionModel[],
): CollectionSchema[] => {
  const viewByFeedId = new Map(
    subscriptions.map((subscription) => [subscription.feedId!, subscription.view] as const),
  )

  return localEntries
    .filter((entry) => entry.starred)
    .map((entry) => ({
      entryId: entry.id,
      feedId: entry.feedId,
      createdAt: new Date(entry.createdAt).toISOString(),
      view: viewByFeedId.get(entry.feedId) ?? FeedViewType.Articles,
    }))
}

const updateUnreadRowsForFeeds = async (feedIds: string[]) => {
  const uniqueFeedIds = Array.from(new Set(feedIds.filter(Boolean)))
  if (uniqueFeedIds.length === 0) {
    return
  }

  const entries = Object.values(useEntryStore.getState().data)
  const rows = uniqueFeedIds.map((feedId) => ({
    id: feedId,
    count: entries.filter((entry) => entry.feedId === feedId && !entry.read).length,
  }))

  for (const row of rows) {
    await unreadActions.updateById(row.id, row.count)
  }
}

const filterLocalEntriesByTime = (entries: LocalEntry[], time?: MarkAllFilter) => {
  if (!time) {
    return entries
  }

  return entries.filter((entry) => {
    if ("startTime" in time) {
      const publishedAt = new Date(entry.publishedAt).getTime()
      return publishedAt >= time.startTime && publishedAt <= time.endTime
    }

    return new Date(entry.createdAt).getTime() < time.insertedBefore
  })
}

const setLocalEntryReadStatus = async (entryIds: string[], read: boolean) => {
  await queueLocalReaderMutation(async () => {
    const uniqueEntryIds = Array.from(new Set(entryIds))
    if (uniqueEntryIds.length === 0) {
      return
    }

    const localReader = getLocalReaderIpc()
    for (const entryId of uniqueEntryIds) {
      await localReader.setEntryRead({ entryId, read })
    }

    entryActions.markEntryReadStatusInSession({
      entryIds: uniqueEntryIds,
      read,
    })
    await EntryService.patchMany({
      entry: { read },
      entryIds: uniqueEntryIds,
    })

    const affectedFeedIds = uniqueEntryIds
      .map((entryId) => getEntry(entryId)?.feedId)
      .filter((feedId): feedId is string => typeof feedId === "string")

    await updateUnreadRowsForFeeds(affectedFeedIds)
  })
}

const getLocalTimelineByFeedIds = async (feedIds: string[]) => {
  const uniqueFeedIds = Array.from(new Set(feedIds)).filter(
    (feedId): feedId is string => typeof feedId === "string" && !!feedId,
  )
  if (uniqueFeedIds.length === 0) {
    return [] as LocalEntry[]
  }

  const localReader = getLocalReaderIpc()
  const timelines = await Promise.all(
    uniqueFeedIds.map((feedId) => localReader.getTimeline({ feedId })),
  )

  return timelines.flat()
}

const getLocalEntriesByFilter = async ({
  view,
  filter,
  excludePrivate,
}: {
  view?: FeedViewType
  filter?: {
    feedId?: string
    listId?: string
    feedIdList?: string[]
    inboxId?: string
  } | null
  excludePrivate: boolean
}) => {
  if (filter?.feedIdList?.length) {
    return getLocalTimelineByFeedIds(filter.feedIdList)
  }

  if (filter?.feedId) {
    return getLocalTimelineByFeedIds([filter.feedId])
  }

  if (filter?.listId) {
    return []
  }

  if (filter?.inboxId) {
    return []
  }

  if (typeof view === "number") {
    const viewFeedIds = getSubscribedFeedIdAndInboxHandlesByView({
      view,
      excludePrivate,
      excludeHidden: true,
    }).filter((feedId) => !!useFeedStore.getState().feeds[feedId])

    return getLocalTimelineByFeedIds(viewFeedIds)
  }

  return [] as LocalEntry[]
}

const persistLocalReaderSnapshot = async (feeds: LocalFeed[], entries: LocalEntry[]) => {
  const entriesByFeedId = new Map<string, LocalEntry[]>(
    feeds.map((feed) => [feed.id, entries.filter((entry) => entry.feedId === feed.id)] as const),
  )

  const feedSchemas = feeds.map((feed) => buildFeedSchema(feed, entriesByFeedId.get(feed.id) ?? []))
  const subscriptions = feeds.map((feed) =>
    buildSubscriptionModel(feed, entriesByFeedId.get(feed.id) ?? []),
  )
  const entrySchemas = entries.map((entry) => {
    const feed = feeds.find((feed) => feed.id === entry.feedId)
    if (!feed) {
      throw new Error(`Missing local feed for entry ${entry.id}`)
    }

    return buildEntrySchema(entry, feed)
  })
  const unreadRows = buildUnreadRows(entrySchemas)
  const collections = buildCollectionsFromLocalEntries(entries, subscriptions)

  await collectionActions.reset()
  await unreadActions.reset()
  await entryActions.reset()
  await subscriptionActions.reset()
  await feedActions.reset()

  if (feedSchemas.length > 0) {
    await feedActions.upsertMany(feedSchemas)
  }
  if (subscriptions.length > 0) {
    await subscriptionActions.upsertMany(subscriptions)
  }
  if (entrySchemas.length > 0) {
    await entryActions.upsertMany(entrySchemas)
  }
  if (unreadRows.length > 0) {
    await unreadActions.upsertMany(unreadRows)
  }
  if (collections.length > 0) {
    await collectionActions.upsertMany(collections)
  }
}

export const syncLocalReaderData = async () => {
  if (!LOCAL_READER_MODE) {
    return
  }

  if (!syncPromise) {
    syncPromise = (async () => {
      await waitForLocalReaderMutations()

      const localReader = getLocalReaderIpc()
      await localReader.initialize()
      const [feeds, entries] = await Promise.all([
        localReader.getFeeds(),
        localReader.getTimeline(),
      ])

      await persistLocalReaderSnapshot(feeds, entries)
    })().finally(() => {
      syncPromise = null
    })
  }

  return syncPromise
}

export const addLocalFeed = async (input: {
  url: string
  category?: string | null
  title?: string | null
  view?: FeedViewType
}) => {
  await getLocalReaderIpc().addFeed(input)
  await syncLocalReaderData()
}

export const updateLocalFeed = async (input: {
  feedId: string
  title?: string | null
  category?: string | null
  view?: FeedViewType
}) => {
  await getLocalReaderIpc().updateFeed(input)
  await syncLocalReaderData()
}

export const updateLocalFeeds = async (
  feedIds: string[],
  patch: Omit<Parameters<typeof updateLocalFeed>[0], "feedId">,
) => {
  const localReader = getLocalReaderIpc()
  await Promise.all(
    feedIds.map((feedId) => localReader.updateFeed({ feedId, ...patch })),
  )
  await syncLocalReaderData()
}

export const deleteLocalFeed = async (feedId: string) => {
  await getLocalReaderIpc().deleteFeed({ feedId })
  await syncLocalReaderData()
}

export const refreshLocalFeed = async (feedId: string) => {
  await waitForLocalReaderMutations()
  await getLocalReaderIpc().refreshFeed({ feedId })
  await syncLocalReaderData()
}

export const refreshAllLocalFeeds = async () => {
  await waitForLocalReaderMutations()
  await getLocalReaderIpc().refreshAll()
  await syncLocalReaderData()
}

export const markLocalEntryAsRead = async (entryId: string) => {
  await setLocalEntryReadStatus([entryId], true)
}

export const markLocalEntryAsUnread = async (entryId: string) => {
  await setLocalEntryReadStatus([entryId], false)
}

export const markLocalFeedAsRead = async (feedId: string | string[]) => {
  const feedIds = Array.isArray(feedId) ? feedId : [feedId]
  const entryIds = (await getLocalTimelineByFeedIds(feedIds)).map((entry) => entry.id)
  await setLocalEntryReadStatus(entryIds, true)
}

export const markLocalBatchAsRead = async ({
  view,
  filter,
  time,
  excludePrivate,
}: {
  view: FeedViewType | undefined
  filter?: {
    feedId?: string
    listId?: string
    feedIdList?: string[]
    inboxId?: string
  } | null
  time?: MarkAllFilter
  excludePrivate: boolean
}) => {
  const entryIds = filterLocalEntriesByTime(
    await getLocalEntriesByFilter({
      view,
      filter,
      excludePrivate,
    }),
    time,
  ).map((entry) => entry.id)

  await setLocalEntryReadStatus(entryIds, true)
}

export const starLocalEntry = async ({
  entryId,
  view,
  invalidate,
}: {
  entryId: string
  view: FeedViewType
  invalidate?: boolean
}) => {
  const entry = getEntry(entryId)
  if (!entry) {
    return
  }

  await getLocalReaderIpc().setEntryStarred({
    entryId,
    starred: true,
  })

  await collectionActions.upsertMany([
    {
      createdAt: new Date().toISOString(),
      entryId,
      feedId: entry.feedId,
      view,
    },
  ])

  if (invalidate) {
    invalidateEntriesQuery({ collection: true })
  }
}

export const unstarLocalEntry = async ({
  entryId,
  invalidate = true,
}: {
  entryId: string
  invalidate?: boolean
}) => {
  await getLocalReaderIpc().setEntryStarred({
    entryId,
    starred: false,
  })

  await collectionActions.delete(entryId)

  if (invalidate) {
    invalidateEntriesQuery({ collection: true })
  }
}

export const subscribeWithLocalReader = async (input: {
  url?: string
  feedId?: string | null
  view?: FeedViewType
  category?: string | null
  title?: string | null
}) => {
  const currentFeedId = input.feedId ?? undefined
  const currentFeed = currentFeedId ? useFeedStore.getState().feeds[currentFeedId] : undefined

  if (currentFeedId && currentFeed) {
    await updateLocalFeed({
      feedId: currentFeedId,
      view: input.view,
      category: input.category,
      title: input.title,
    })
    return
  }

  if (!input.url) {
    throw new Error("Feed URL is required")
  }

  await addLocalFeed({
    url: input.url,
    category: input.category,
    title: input.title,
    view: input.view,
  })
}

export const unsubscribeWithLocalReader = async (feedIds: string[]) => {
  const deletedFeeds = feedIds
    .map((feedId) => useFeedStore.getState().feeds[feedId])
    .filter(Boolean)
    .map((feed) => ({
      ...feed,
      type: "feed" as const,
    }))

  const localReader = getLocalReaderIpc()
  await Promise.all(feedIds.map((feedId) => localReader.deleteFeed({ feedId })))
  await syncLocalReaderData()

  return deletedFeeds
}

export const changeLocalCategoryView = async ({
  category,
  currentView,
  newView,
}: {
  category: string
  currentView: FeedViewType
  newView: FeedViewType
}) => {
  const feedIds = getCategoryFeedIds(category, currentView)
  await updateLocalFeeds(feedIds, { view: newView })
}
