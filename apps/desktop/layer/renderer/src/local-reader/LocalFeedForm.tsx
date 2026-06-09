import { Button } from "@follow/components/ui/button/index.js"
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@follow/components/ui/form/index.jsx"
import { Input } from "@follow/components/ui/input/index.js"
import { FeedViewType } from "@follow/constants"
import { useFeedByIdOrUrl } from "@follow/store/feed/hooks"
import { useSubscriptionByFeedId } from "@follow/store/subscription/hooks"
import { zodResolver } from "@hookform/resolvers/zod"
import { useMutation } from "@tanstack/react-query"
import { useCallback, useEffect } from "react"
import { useForm } from "react-hook-form"
import { toast } from "sonner"
import { z } from "zod"

import { useModalStack } from "~/components/ui/modal/stacked/hooks"
import { getRouteParams } from "~/hooks/biz/useRouteParams"
import { ViewSelectorRadioGroup } from "~/modules/shared/ViewSelectorRadioGroup"

import { addLocalFeed, updateLocalFeed } from "./service"

const formSchema = z.object({
  url: z.string().trim().min(1, "请输入订阅地址"),
  title: z.string().trim().optional(),
  category: z.string().trim().optional(),
  view: z.string().min(1, "请选择订阅视图"),
})

type LocalFeedFormValues = z.infer<typeof formSchema>

export interface LocalFeedFormDefaultValues {
  title?: string
  category?: string | null
  view?: number
}

export const LocalFeedForm: Component<{
  feedId?: string
  url?: string
  defaultValues?: LocalFeedFormDefaultValues
  onSuccess?: () => void
}> = ({ feedId, url, defaultValues, onSuccess }) => {
  const feed = useFeedByIdOrUrl({
    id: feedId,
    url,
  })
  const subscription = useSubscriptionByFeedId(feed?.id || feedId || "")
  const isEditing = Boolean(feed)

  const form = useForm<LocalFeedFormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      url: url ?? "",
      title: defaultValues?.title ?? "",
      category: defaultValues?.category ?? "",
      view: String(defaultValues?.view ?? getRouteParams().view ?? FeedViewType.Articles),
    },
  })

  useEffect(() => {
    if (!feed) {
      return
    }

    form.reset({
      url: feed.url,
      title: defaultValues?.title ?? subscription?.title ?? feed.title ?? "",
      category: defaultValues?.category ?? subscription?.category ?? "",
      view: String(defaultValues?.view ?? subscription?.view ?? FeedViewType.Articles),
    })
  }, [defaultValues?.category, defaultValues?.title, defaultValues?.view, feed, form, subscription])

  const mutation = useMutation({
    mutationFn: async (values: LocalFeedFormValues) => {
      const payload = {
        title: values.title?.trim() || null,
        category: values.category?.trim() || null,
        view: Number(values.view) as FeedViewType,
      }

      if (feed?.id) {
        await updateLocalFeed({
          feedId: feed.id,
          ...payload,
        })
      } else {
        await addLocalFeed({
          url: values.url.trim(),
          ...payload,
        })
      }
    },
    onSuccess: () => {
      toast.success(isEditing ? "订阅已更新" : "订阅已添加")
      onSuccess?.()
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : "操作失败")
    },
  })

  const handleFillDefaultTitle = useCallback(() => {
    if (!feed?.title) {
      return
    }

    form.setValue("title", feed.title, { shouldDirty: true, shouldValidate: true })
  }, [feed?.title, form])

  return (
    <Form {...form}>
      <form
        id="local-feed-form"
        onSubmit={form.handleSubmit((values) => mutation.mutate(values))}
        className="flex w-full max-w-[560px] flex-col gap-4"
      >
        <FormField
          control={form.control}
          name="url"
          render={({ field }) => (
            <FormItem>
              <FormLabel>订阅地址</FormLabel>
              <FormControl>
                <Input
                  {...field}
                  disabled={isEditing}
                  placeholder="https://example.com/feed.xml"
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="title"
          render={({ field }) => (
            <FormItem>
              <FormLabel>显示名称</FormLabel>
              <FormControl>
                <div className="flex gap-2">
                  <Input {...field} placeholder={feed?.title || "保留 RSS 默认标题"} />
                  {feed?.title && (
                    <Button
                      type="button"
                      variant="outline"
                      buttonClassName="shrink-0"
                      onClick={handleFillDefaultTitle}
                    >
                      使用默认
                    </Button>
                  )}
                </div>
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="category"
          render={({ field }) => (
            <FormItem>
              <FormLabel>分类</FormLabel>
              <FormControl>
                <Input {...field} placeholder="例如：科技、视频、设计" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="view"
          render={() => (
            <FormItem>
              <FormLabel>视图</FormLabel>
              <ViewSelectorRadioGroup
                {...form.register("view")}
                feed={feed}
                view={Number(form.getValues("view"))}
              />
              <FormMessage />
            </FormItem>
          )}
        />

        <div className="flex items-center justify-end gap-3 pt-2">
          <Button type="submit" isLoading={mutation.isPending}>
            {isEditing ? "保存修改" : "添加订阅"}
          </Button>
        </div>
      </form>
    </Form>
  )
}

export const usePresentLocalFeedModal = () => {
  const { present } = useModalStack()

  return useCallback(
    (options?: {
      feedId?: string
      url?: string
      defaultValues?: LocalFeedFormDefaultValues
      onSuccess?: () => void
    }) => {
      present({
        title: options?.feedId ? "编辑订阅" : "添加订阅",
        modalContentClassName: "overflow-visible",
        content: ({ dismiss }) => (
          <LocalFeedForm
            feedId={options?.feedId}
            url={options?.url}
            defaultValues={options?.defaultValues}
            onSuccess={() => {
              options?.onSuccess?.()
              dismiss()
            }}
          />
        ),
      })
    },
    [present],
  )
}
