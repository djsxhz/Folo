import type { FeedViewType } from "@follow/constants"
import { getCategoryFeedIds } from "@follow/store/subscription/getter"
import { unreadSyncService } from "@follow/store/unread/store"

import { getGeneralSettings } from "~/atoms/settings/general"
import { LOCAL_READER_MODE } from "~/local-reader/mode"
import { markLocalBatchAsRead } from "~/local-reader/service"

export type MarkAllFilter =
  | {
      startTime: number
      endTime: number
    }
  | {
      insertedBefore: number
    }

export const markAllByRoute = async (
  data: {
    feedId?: string | undefined
    view: FeedViewType
    inboxId?: string | undefined
    listId?: string | undefined

    isAllFeeds?: boolean
  },
  time?: MarkAllFilter,
) => {
  const { feedId, view, inboxId, listId, isAllFeeds } = data
  const folderIds = getCategoryFeedIds(feedId, view)

  if (!feedId) return

  const { hidePrivateSubscriptionsInTimeline: excludePrivate } = getGeneralSettings()
  if (typeof feedId === "number" || isAllFeeds) {
    const input = {
      view,
      time,
      excludePrivate,
    }
    if (LOCAL_READER_MODE) {
      return markLocalBatchAsRead(input)
    } else {
      unreadSyncService.markBatchAsRead(input)
      return
    }
  } else if (inboxId) {
    const input = {
      filter: {
        inboxId,
      },
      view,
      time,
      excludePrivate,
    }
    if (LOCAL_READER_MODE) {
      return markLocalBatchAsRead(input)
    } else {
      unreadSyncService.markBatchAsRead(input)
      return
    }
  } else if (listId) {
    const input = {
      filter: {
        listId,
      },
      view,
      time,
      excludePrivate,
    }
    if (LOCAL_READER_MODE) {
      return markLocalBatchAsRead(input)
    } else {
      unreadSyncService.markBatchAsRead(input)
      return
    }
  } else if (folderIds?.length) {
    const input = {
      filter: {
        feedIdList: folderIds,
      },
      view,
      time,
      excludePrivate,
    }
    if (LOCAL_READER_MODE) {
      return markLocalBatchAsRead(input)
    } else {
      unreadSyncService.markBatchAsRead(input)
      return
    }
  } else if (feedId) {
    const input = {
      filter: {
        feedIdList: feedId?.split(","),
      },
      view,
      time,
      excludePrivate,
    }
    if (LOCAL_READER_MODE) {
      return markLocalBatchAsRead(input)
    } else {
      unreadSyncService.markBatchAsRead(input)
      return
    }
  }
}
