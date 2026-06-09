import { getFeedByIdOrUrl } from "@follow/store/feed/getter"
import { getSubscriptionByFeedId } from "@follow/store/subscription/getter"
import { t } from "i18next"
import { useCallback } from "react"
import { useNavigate } from "react-router"
import { withoutTrailingSlash, withTrailingSlash } from "ufo"

import { previewBackPath } from "~/atoms/preview"
import { useModalStack } from "~/components/ui/modal/stacked/hooks"
import { LocalFeedForm } from "~/local-reader/LocalFeedForm"
import { LOCAL_READER_MODE } from "~/local-reader/mode"
import type { FeedFormDataValuesType } from "~/modules/discover/FeedForm"
import { FeedForm } from "~/modules/discover/FeedForm"
import type { ListFormDataValuesType } from "~/modules/discover/ListForm"
import { ListForm } from "~/modules/discover/ListForm"

export interface FollowOptions {
  isList: boolean
  id?: string
  url?: string

  onSuccess?: () => void
  defaultValues?: Partial<ListFormDataValuesType> | Partial<FeedFormDataValuesType>
}
export const useFollow = () => {
  const { present } = useModalStack()
  const navigate = useNavigate()

  return useCallback(
    (options?: FollowOptions) => {
      // Some feeds redirect xxx.com/feed to xxx.com/feed/
      // Try to get a valid feed, then we can check isFollowed correctly
      const feed =
        getFeedByIdOrUrl({ id: options?.id, url: withTrailingSlash(options?.url) }) ??
        getFeedByIdOrUrl({ id: options?.id, url: withoutTrailingSlash(options?.url) })
      const id = options?.id || feed?.id
      const url = feed?.type === "feed" ? feed.url : options?.url
      const subscription = getSubscriptionByFeedId(id)
      const isFollowed = !!subscription

      present({
        title: `${isFollowed ? `${t("common:words.edit")} ` : ""}${options?.isList ? t("words.lists") : t("words.feeds")}`,
        modalContentClassName: "overflow-visible",
        content: ({ dismiss }) => {
          const onSuccess = () => {
            options?.onSuccess?.()
            // If it's a preview, navigate to the back path
            const backPath = previewBackPath()
            backPath && navigate(backPath)
            dismiss()
          }
          return options?.isList ? (
            <ListForm
              id={options?.id}
              defaultValues={options?.defaultValues as ListFormDataValuesType}
              onSuccess={onSuccess}
            />
          ) : LOCAL_READER_MODE ? (
            <LocalFeedForm
              feedId={id}
              url={url}
              defaultValues={
                options?.defaultValues
                  ? {
                      title:
                        "title" in options.defaultValues
                          ? (options.defaultValues.title as string | undefined)
                          : undefined,
                      category:
                        "category" in options.defaultValues
                          ? ((options.defaultValues.category as string | null | undefined) ?? null)
                          : null,
                      view:
                        "view" in options.defaultValues
                          ? Number(options.defaultValues.view)
                          : undefined,
                    }
                  : undefined
              }
              onSuccess={onSuccess}
            />
          ) : (
            <FeedForm
              id={id}
              url={url}
              defaultValues={options?.defaultValues as FeedFormDataValuesType}
              onSuccess={onSuccess}
            />
          )
        },
      })
    },
    [present],
  )
}
