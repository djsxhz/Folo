import { mkdir } from "node:fs/promises"

import { FeedViewType } from "@follow/constants"
import { transformVideoUrl } from "@follow/utils/url-for-video"
import { DOMParser } from "@xmldom/xmldom"
import { app } from "electron"
import { Low } from "lowdb"
import { JSONFile } from "lowdb/node"
import { nanoid } from "nanoid"
import path from "pathe"

export interface LocalReaderFeedRecord {
  id: string
  title: string
  url: string
  siteUrl: string | null
  description: string | null
  imageUrl: string | null
  category: string | null
  view: FeedViewType
  createdAt: number
  lastFetchedAt: number | null
  lastError: string | null
}

export interface LocalReaderAttachment {
  url: string
  mimeType?: string | null
}

export interface LocalReaderEntryRecord {
  id: string
  guid: string
  feedId: string
  title: string
  url: string | null
  author: string | null
  excerpt: string | null
  contentHtml: string | null
  publishedAt: number
  createdAt: number
  read: boolean
  starred: boolean
  kind: "article" | "video"
  thumbnailUrl: string | null
  embedUrl: string | null
  videoUrl: string | null
  attachments: LocalReaderAttachment[]
}

export interface LocalReaderSettings {
  language: "zh-CN"
  refreshIntervalMinutes: number
}

interface LocalReaderDatabase {
  feeds: LocalReaderFeedRecord[]
  entries: LocalReaderEntryRecord[]
  settings: LocalReaderSettings
}

interface XmlNodeLike {
  textContent: string | null
  getAttribute: (name: string) => string | null
  getElementsByTagName: (name: string) => ArrayLike<XmlNodeLike>
}

interface XmlDocumentLike {
  getElementsByTagName: (name: string) => ArrayLike<XmlNodeLike>
}

interface ParsedEntryDraft {
  guid: string
  title: string
  url: string | null
  author: string | null
  excerpt: string | null
  contentHtml: string | null
  publishedAt: number
  kind: "article" | "video"
  thumbnailUrl: string | null
  embedUrl: string | null
  videoUrl: string | null
  attachments: LocalReaderAttachment[]
}

interface ParsedFeedResult {
  title: string | null
  siteUrl: string | null
  description: string | null
  imageUrl: string | null
  entries: ParsedEntryDraft[]
}

const IMAGE_URL_PATTERN = /\.(avif|bmp|gif|jpe?g|png|svg|webp)(?:[?#]|$)/i

function isImageAttachment(attachment: LocalReaderAttachment) {
  if (attachment.mimeType?.startsWith("image")) {
    return true
  }

  return IMAGE_URL_PATTERN.test(attachment.url)
}

export interface TimelineQuery {
  feedId?: string
  category?: string
  starredOnly?: boolean
  videosOnly?: boolean
  search?: string
}

export interface TimelineEntryView extends LocalReaderEntryRecord {
  feedTitle: string
  feedImageUrl: string | null
  category: string | null
}

export interface EntryDetailView extends TimelineEntryView {}

export interface FeedView extends LocalReaderFeedRecord {
  entryCount: number
  unreadCount: number
  videoCount: number
}

export interface CategoryView {
  name: string
  feedCount: number
  unreadCount: number
}

const DATABASE_DIR = "local-reader"
const DATABASE_FILE = "database.json"
const DEFAULT_REFRESH_INTERVAL_MINUTES = 30
const FEED_FETCH_HEADERS = {
  Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) LocalReader/1.0 Safari/537.36",
}

let databasePromise: Promise<Low<LocalReaderDatabase>> | null = null
let databaseWritePromise: Promise<void> = Promise.resolve()
let refreshTimer: NodeJS.Timeout | null = null

function createDefaultDatabase(): LocalReaderDatabase {
  return {
    feeds: [],
    entries: [],
    settings: {
      language: "zh-CN",
      refreshIntervalMinutes: DEFAULT_REFRESH_INTERVAL_MINUTES,
    },
  }
}

async function getDatabase() {
  if (!databasePromise) {
    databasePromise = (async () => {
      const directory = path.join(app.getPath("userData"), DATABASE_DIR)
      await mkdir(directory, { recursive: true })

      const adapter = new JSONFile<LocalReaderDatabase>(path.join(directory, DATABASE_FILE))
      const database = new Low(adapter, createDefaultDatabase())
      await database.read()
      database.data ||= createDefaultDatabase()
      await database.write()

      return database
    })()
  }

  return databasePromise
}

async function withReadonlyDatabase<T>(reader: (database: LocalReaderDatabase) => T | Promise<T>) {
  await databaseWritePromise
  const database = await getDatabase()
  await database.read()
  database.data ||= createDefaultDatabase()

  return reader(database.data)
}

async function withWritableDatabase<T>(
  updater: (database: LocalReaderDatabase) => T | Promise<T>,
) {
  const run = async () => {
    const database = await getDatabase()
    await database.read()
    database.data ||= createDefaultDatabase()

    const result = await updater(database.data)

    await database.write()
    return result
  }

  // Serialize writes so concurrent local-reader mutations do not overwrite each
  // other while persisting the shared LowDB JSON snapshot.
  const nextTask = databaseWritePromise.then(run, run)
  databaseWritePromise = nextTask.then(
    () => undefined,
    () => undefined,
  )

  return nextTask
}

function normalizeText(value: string | null | undefined) {
  const normalized = value?.replaceAll(/\s+/g, " ").trim()
  return normalized || null
}

function normalizeCategory(category: string | null | undefined) {
  return normalizeText(category)
}

function inferFeedViewFromEntries(entries: Array<{ kind: "article" | "video" }>) {
  if (entries.length === 0) {
    return FeedViewType.Articles
  }

  const videoCount = entries.filter((entry) => entry.kind === "video").length
  return videoCount > 0 && videoCount >= Math.ceil(entries.length / 2)
    ? FeedViewType.Videos
    : FeedViewType.Articles
}

function normalizeFeedView(
  view: FeedViewType | number | null | undefined,
  entries: Array<{ kind: "article" | "video" }>,
) {
  if (typeof view === "number") {
    return view as FeedViewType
  }

  return inferFeedViewFromEntries(entries)
}

function getNodeList(source: XmlDocumentLike | XmlNodeLike, name: string) {
  // xmldom XML nodes do not reliably support querySelectorAll for namespaced tags.
  // eslint-disable-next-line unicorn/prefer-query-selector
  return Array.from(source.getElementsByTagName(name))
}

function getFirstNode(source: XmlDocumentLike | XmlNodeLike, names: string[]) {
  for (const name of names) {
    const node = getNodeList(source, name)[0]
    if (node) {
      return node
    }
  }

  return null
}

function getFirstText(source: XmlDocumentLike | XmlNodeLike, names: string[]) {
  return normalizeText(getFirstNode(source, names)?.textContent ?? null)
}

function getLinkFromAtom(entry: XmlNodeLike) {
  const links = getNodeList(entry, "link")
  const alternateLink =
    links.find((item) => (item.getAttribute("rel") ?? "alternate") === "alternate") ?? links[0]

  return normalizeText(alternateLink?.getAttribute("href"))
}

function getFirstAttr(source: XmlDocumentLike | XmlNodeLike, names: string[], attribute: string) {
  for (const name of names) {
    const node = getNodeList(source, name)[0]
    const value = normalizeText(node?.getAttribute(attribute) ?? null)
    if (value) {
      return value
    }
  }

  return null
}

function parsePublishedAt(value: string | null) {
  if (!value) {
    return Date.now()
  }

  const parsed = Date.parse(value)
  return Number.isNaN(parsed) ? Date.now() : parsed
}

function decodeHtmlEntities(input: string) {
  const entityMap: Record<string, string> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: '"',
  }

  return input.replaceAll(/&(#x?[0-9a-f]+|[a-z]+);/gi, (match, entity) => {
    const normalizedEntity = entity.toLowerCase()

    if (normalizedEntity.startsWith("#x")) {
      const codePoint = Number.parseInt(normalizedEntity.slice(2), 16)
      return Number.isNaN(codePoint) ? match : String.fromCodePoint(codePoint)
    }

    if (normalizedEntity.startsWith("#")) {
      const codePoint = Number.parseInt(normalizedEntity.slice(1), 10)
      return Number.isNaN(codePoint) ? match : String.fromCodePoint(codePoint)
    }

    return entityMap[normalizedEntity] ?? match
  })
}

function getFirstHtmlAttributeValue(input: string, tagNames: string[], attribute: string) {
  const tags = tagNames.join("|")
  const expression = new RegExp(
    `<(?:${tags})\\b[^>]*\\s${attribute}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'` + "`" + `=<>]+))`,
    "i",
  )
  const match = expression.exec(input)

  return normalizeText(
    decodeHtmlEntities(match?.[1] ?? match?.[2] ?? match?.[3] ?? ""),
  )
}

function stripHtml(input: string | null) {
  if (!input) {
    return null
  }

  const plainText = decodeHtmlEntities(
    input
      .replaceAll(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
      .replaceAll(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
      .replaceAll(/<br\s*\/?>/gi, "\n")
      .replaceAll(/<\/(p|div|section|article|li|h[1-6])>/gi, "\n")
      .replaceAll(/<[^>]+>/g, " "),
  )

  return normalizeText(plainText)
}

function extractHtmlMedia(contentHtml: string | null) {
  if (!contentHtml) {
    return {
      firstImageUrl: null,
      iframeSrc: null,
      videoSrc: null,
    }
  }

  return {
    firstImageUrl: getFirstHtmlAttributeValue(contentHtml, ["img"], "src"),
    iframeSrc: getFirstHtmlAttributeValue(contentHtml, ["iframe"], "src"),
    videoSrc:
      getFirstHtmlAttributeValue(contentHtml, ["source"], "src") ??
      getFirstHtmlAttributeValue(contentHtml, ["video"], "src"),
  }
}

function normalizeEmbeddedVideoUrl(url: string | null) {
  if (!url) {
    return null
  }

  if (
    /youtube(?:-nocookie)?\.com\/embed\//.test(url) ||
    /player\.bilibili\.com\/player\.html/.test(url)
  ) {
    return url
  }

  return null
}

function collectRssAttachments(item: XmlNodeLike) {
  const attachments: LocalReaderAttachment[] = []

  const enclosureNodes = [...getNodeList(item, "enclosure"), ...getNodeList(item, "media:content")]

  for (const enclosure of enclosureNodes) {
    const url = normalizeText(enclosure.getAttribute("url"))
    if (!url) {
      continue
    }

    attachments.push({
      url,
      mimeType:
        normalizeText(enclosure.getAttribute("type")) ??
        normalizeText(enclosure.getAttribute("medium")),
    })
  }

  return dedupeAttachments(attachments)
}

function collectAtomAttachments(entry: XmlNodeLike) {
  const attachments: LocalReaderAttachment[] = []
  const links = getNodeList(entry, "link")

  for (const link of links) {
    if ((link.getAttribute("rel") ?? "") !== "enclosure") {
      continue
    }

    const url = normalizeText(link.getAttribute("href"))
    if (!url) {
      continue
    }

    attachments.push({
      url,
      mimeType: normalizeText(link.getAttribute("type")),
    })
  }

  return dedupeAttachments(attachments)
}

function dedupeAttachments(attachments: LocalReaderAttachment[]) {
  const seen = new Set<string>()

  return attachments.filter((attachment) => {
    const key = `${attachment.url}::${attachment.mimeType ?? ""}`
    if (seen.has(key)) {
      return false
    }

    seen.add(key)
    return true
  })
}

function resolveVideoFields(
  url: string | null,
  contentHtml: string | null,
  attachments: LocalReaderAttachment[],
) {
  const htmlMedia = extractHtmlMedia(contentHtml)
  const transformedUrl = url
    ? transformVideoUrl({
        url,
        attachments: attachments.map((attachment) => ({
          url: attachment.url,
          mime_type: attachment.mimeType ?? undefined,
        })),
      })
    : null

  const directVideoUrl =
    attachments.find((attachment) => attachment.mimeType?.startsWith("video"))?.url ??
    htmlMedia.videoSrc
  const attachmentThumbnailUrl = attachments.find((attachment) => isImageAttachment(attachment))?.url

  const embedUrl = transformedUrl ?? normalizeEmbeddedVideoUrl(htmlMedia.iframeSrc)

  return {
    kind: embedUrl || directVideoUrl ? "video" : "article",
    thumbnailUrl: htmlMedia.firstImageUrl ?? attachmentThumbnailUrl ?? null,
    embedUrl,
    videoUrl: directVideoUrl ?? null,
  } as const
}

function parseRssFeed(document: XmlDocumentLike) {
  const channel = getFirstNode(document, ["channel"])
  const items = getNodeList(document, "item")

  const entries: ParsedEntryDraft[] = items.map((item) => {
    const url = getFirstText(item, ["link"])
    const contentHtml =
      getFirstText(item, ["content:encoded", "description"]) ??
      getFirstText(item, ["summary"]) ??
      null
    const attachments = collectRssAttachments(item)
    const videoFields = resolveVideoFields(url, contentHtml, attachments)
    const excerpt = stripHtml(contentHtml) ?? getFirstText(item, ["description"])
    const thumbnailUrl =
      getFirstAttr(item, ["media:thumbnail"], "url") ??
      getFirstAttr(item, ["media:content"], "url") ??
      videoFields.thumbnailUrl

    return {
      guid:
        getFirstText(item, ["guid"]) ??
        url ??
        `${getFirstText(item, ["title"]) ?? "entry"}-${parsePublishedAt(
          getFirstText(item, ["pubDate", "dc:date"]),
        )}`,
      title: getFirstText(item, ["title"]) ?? "未命名内容",
      url,
      author: getFirstText(item, ["creator", "author", "dc:creator"]),
      excerpt,
      contentHtml,
      publishedAt: parsePublishedAt(getFirstText(item, ["pubDate", "dc:date"])),
      kind: videoFields.kind,
      thumbnailUrl,
      embedUrl: videoFields.embedUrl,
      videoUrl: videoFields.videoUrl,
      attachments,
    }
  })

  return {
    title: getFirstText(channel ?? document, ["title"]),
    siteUrl: getFirstText(channel ?? document, ["link"]),
    description: getFirstText(channel ?? document, ["description"]),
    imageUrl:
      getFirstAttr(channel ?? document, ["itunes:image"], "href") ??
      getFirstText(getFirstNode(channel ?? document, ["image"]) ?? (channel ?? document), ["url"]),
    entries,
  } satisfies ParsedFeedResult
}

function parseAtomFeed(document: XmlDocumentLike) {
  const feed = getFirstNode(document, ["feed"])
  const entries = getNodeList(document, "entry").map((entry) => {
    const url = getLinkFromAtom(entry)
    const contentHtml = getFirstText(entry, ["content", "summary"])
    const attachments = collectAtomAttachments(entry)
    const videoFields = resolveVideoFields(url, contentHtml, attachments)
    const thumbnailUrl =
      getFirstAttr(entry, ["media:thumbnail"], "url") ??
      getFirstAttr(entry, ["media:group"], "url") ??
      videoFields.thumbnailUrl

    return {
      guid:
        getFirstText(entry, ["id"]) ??
        url ??
        `${getFirstText(entry, ["title"]) ?? "entry"}-${parsePublishedAt(
          getFirstText(entry, ["published", "updated"]),
        )}`,
      title: getFirstText(entry, ["title"]) ?? "未命名内容",
      url,
      author:
        getFirstText(getFirstNode(entry, ["author"]) ?? entry, ["name"]) ??
        getFirstText(entry, ["author"]),
      excerpt: stripHtml(contentHtml) ?? getFirstText(entry, ["summary"]),
      contentHtml,
      publishedAt: parsePublishedAt(getFirstText(entry, ["published", "updated"])),
      kind: videoFields.kind,
      thumbnailUrl,
      embedUrl: videoFields.embedUrl,
      videoUrl: videoFields.videoUrl,
      attachments,
    }
  })

  return {
    title: getFirstText(feed ?? document, ["title"]),
    siteUrl: getFirstAttr(feed ?? document, ["link"], "href"),
    description: getFirstText(feed ?? document, ["subtitle"]),
    imageUrl: getFirstText(feed ?? document, ["icon", "logo"]),
    entries,
  } satisfies ParsedFeedResult
}

async function parseFeed(url: string) {
  const response = await fetch(url, { headers: FEED_FETCH_HEADERS })

  if (!response.ok) {
    throw new Error(`抓取失败：${response.status} ${response.statusText}`)
  }

  const xml = await response.text()
  const document = new DOMParser().parseFromString(xml, "text/xml") as unknown as XmlDocumentLike
  const itemCount = getNodeList(document, "item").length
  const entryCount = getNodeList(document, "entry").length

  if (itemCount === 0 && entryCount === 0) {
    throw new Error("未识别到有效的 RSS 或 Atom 内容")
  }

  return itemCount > 0 ? parseRssFeed(document) : parseAtomFeed(document)
}

function getFeedStats(entries: LocalReaderEntryRecord[], feedId: string) {
  const targetEntries = entries.filter((entry) => entry.feedId === feedId)

  return {
    entryCount: targetEntries.length,
    unreadCount: targetEntries.filter((entry) => !entry.read).length,
    videoCount: targetEntries.filter((entry) => entry.kind === "video").length,
  }
}

function sortEntries(entries: LocalReaderEntryRecord[]) {
  return [...entries].sort((left, right) => right.publishedAt - left.publishedAt)
}

function matchesSearch(entry: LocalReaderEntryRecord, search: string | undefined) {
  if (!search) {
    return true
  }

  const keyword = search.trim().toLowerCase()
  if (!keyword) {
    return true
  }

  return [entry.title, entry.author, entry.excerpt, entry.contentHtml]
    .filter(Boolean)
    .some((value) => value!.toLowerCase().includes(keyword))
}

function buildTimelineEntries(
  database: LocalReaderDatabase,
  query: TimelineQuery = {},
): TimelineEntryView[] {
  const feedById = new Map(database.feeds.map((feed) => [feed.id, feed]))

  return sortEntries(database.entries)
    .filter((entry) => {
      if (query.feedId && entry.feedId !== query.feedId) {
        return false
      }

      const feed = feedById.get(entry.feedId)
      if (query.category && feed?.category !== query.category) {
        return false
      }

      if (query.starredOnly && !entry.starred) {
        return false
      }

      if (query.videosOnly && entry.kind !== "video") {
        return false
      }

      return matchesSearch(entry, query.search)
    })
    .map((entry) => {
      const feed = feedById.get(entry.feedId)

      return {
        ...entry,
        feedTitle: feed?.title ?? "未命名订阅源",
        feedImageUrl: feed?.imageUrl ?? null,
        category: feed?.category ?? null,
      }
    })
}

function buildFeedView(database: LocalReaderDatabase): FeedView[] {
  return database.feeds
    .map((feed) => {
      const feedEntries = database.entries.filter((entry) => entry.feedId === feed.id)
      return {
        ...feed,
        view: normalizeFeedView(feed.view, feedEntries),
        ...getFeedStats(database.entries, feed.id),
      }
    })
    .sort((left, right) => {
      if (right.unreadCount !== left.unreadCount) {
        return right.unreadCount - left.unreadCount
      }

      return left.title.localeCompare(right.title, "zh-CN")
    })
}

function buildCategoryView(database: LocalReaderDatabase): CategoryView[] {
  const map = new Map<string, CategoryView>()

  for (const feed of database.feeds) {
    if (!feed.category) {
      continue
    }

    const current = map.get(feed.category) ?? {
      name: feed.category,
      feedCount: 0,
      unreadCount: 0,
    }
    const stats = getFeedStats(database.entries, feed.id)

    current.feedCount += 1
    current.unreadCount += stats.unreadCount
    map.set(feed.category, current)
  }

  return [...map.values()].sort((left, right) => left.name.localeCompare(right.name, "zh-CN"))
}

function buildEntryDetail(database: LocalReaderDatabase, entryId: string): EntryDetailView | null {
  const entry = database.entries.find((item) => item.id === entryId)
  if (!entry) {
    return null
  }

  const feed = database.feeds.find((item) => item.id === entry.feedId)

  return {
    ...entry,
    feedTitle: feed?.title ?? "未命名订阅源",
    feedImageUrl: feed?.imageUrl ?? null,
    category: feed?.category ?? null,
  }
}

async function updateRefreshTimer() {
  const database = await getDatabase()
  const refreshIntervalMinutes = Math.max(5, database.data?.settings.refreshIntervalMinutes ?? 30)

  if (refreshTimer) {
    clearInterval(refreshTimer)
  }

  refreshTimer = setInterval(() => {
    void refreshAllFeeds()
  }, refreshIntervalMinutes * 60 * 1000)
}

async function upsertEntries(
  database: LocalReaderDatabase,
  feed: LocalReaderFeedRecord,
  parsedEntries: ParsedEntryDraft[],
) {
  const existingEntries = new Map<string, LocalReaderEntryRecord>(
    database.entries
      .filter((entry) => entry.feedId === feed.id)
      .map((entry) => [`${entry.feedId}::${entry.guid}`, entry] as const),
  )

  for (const parsedEntry of parsedEntries) {
    const key = `${feed.id}::${parsedEntry.guid}`
    const existingEntry = existingEntries.get(key)

    if (existingEntry) {
      existingEntry.title = parsedEntry.title
      existingEntry.url = parsedEntry.url
      existingEntry.author = parsedEntry.author
      existingEntry.excerpt = parsedEntry.excerpt
      existingEntry.contentHtml = parsedEntry.contentHtml
      existingEntry.publishedAt = parsedEntry.publishedAt
      existingEntry.kind = parsedEntry.kind
      existingEntry.thumbnailUrl = parsedEntry.thumbnailUrl
      existingEntry.embedUrl = parsedEntry.embedUrl
      existingEntry.videoUrl = parsedEntry.videoUrl
      existingEntry.attachments = parsedEntry.attachments
      continue
    }

    database.entries.push({
      id: nanoid(),
      feedId: feed.id,
      createdAt: Date.now(),
      read: false,
      starred: false,
      ...parsedEntry,
    })
  }
}

export async function initializeLocalReaderEngine() {
  await getDatabase()
  await updateRefreshTimer()
}

export async function getFeeds() {
  return withReadonlyDatabase(async (database) => buildFeedView(database))
}

export async function getCategories() {
  return withReadonlyDatabase(async (database) => buildCategoryView(database))
}

export async function getSettings() {
  return withReadonlyDatabase(async (database) => database.settings)
}

export async function getTimeline(query: TimelineQuery = {}) {
  return withReadonlyDatabase(async (database) => buildTimelineEntries(database, query))
}

export async function getEntry(entryId: string) {
  return withReadonlyDatabase(async (database) => buildEntryDetail(database, entryId))
}

export async function addFeed(input: {
  url: string
  category?: string | null
  title?: string | null
  view?: FeedViewType
}) {
  const url = normalizeText(input.url)
  if (!url) {
    throw new Error("请输入有效的订阅地址")
  }

  const parsedFeed = await parseFeed(url)

  return withWritableDatabase(async (database) => {
    const existingFeed = database.feeds.find((feed) => feed.url === url)
    if (existingFeed) {
      throw new Error("这个订阅已经存在了")
    }

    const feed: LocalReaderFeedRecord = {
      id: nanoid(),
      title: normalizeText(input.title) ?? parsedFeed.title ?? url,
      url,
      siteUrl: parsedFeed.siteUrl,
      description: parsedFeed.description,
      imageUrl: parsedFeed.imageUrl,
      category: normalizeCategory(input.category),
      view: normalizeFeedView(input.view, parsedFeed.entries),
      createdAt: Date.now(),
      lastFetchedAt: Date.now(),
      lastError: null,
    }

    database.feeds.push(feed)
    await upsertEntries(database, feed, parsedFeed.entries)

    return feed
  })
}

export async function updateFeed(input: {
  feedId: string
  title?: string | null
  category?: string | null
  view?: FeedViewType
}) {
  return withWritableDatabase(async (database) => {
    const feed = database.feeds.find((item) => item.id === input.feedId)
    if (!feed) {
      throw new Error("订阅不存在")
    }

    if (input.title !== undefined) {
      feed.title = normalizeText(input.title) ?? feed.title
    }

    if (input.category !== undefined) {
      feed.category = normalizeCategory(input.category)
    }

    if (input.view !== undefined) {
      feed.view = input.view
    }

    return feed
  })
}

export async function deleteFeed(feedId: string) {
  return withWritableDatabase(async (database) => {
    const nextFeeds = database.feeds.filter((feed) => feed.id !== feedId)
    if (nextFeeds.length === database.feeds.length) {
      throw new Error("订阅不存在")
    }

    database.feeds = nextFeeds
    database.entries = database.entries.filter((entry) => entry.feedId !== feedId)

    return { success: true }
  })
}

export async function refreshFeed(feedId: string) {
  return withWritableDatabase(async (database) => {
    const feed = database.feeds.find((item) => item.id === feedId)
    if (!feed) {
      throw new Error("订阅不存在")
    }

    const parsedFeed = await parseFeed(feed.url)

    feed.title = parsedFeed.title ?? feed.title
    feed.siteUrl = parsedFeed.siteUrl
    feed.description = parsedFeed.description
    feed.imageUrl = parsedFeed.imageUrl
    feed.lastFetchedAt = Date.now()
    feed.lastError = null

    await upsertEntries(database, feed, parsedFeed.entries)

    return feed
  })
}

export async function refreshAllFeeds() {
  return withWritableDatabase(async (database) => {
    for (const feed of database.feeds) {
      try {
        const parsedFeed = await parseFeed(feed.url)

        feed.title = parsedFeed.title ?? feed.title
        feed.siteUrl = parsedFeed.siteUrl
        feed.description = parsedFeed.description
        feed.imageUrl = parsedFeed.imageUrl
        feed.lastFetchedAt = Date.now()
        feed.lastError = null

        await upsertEntries(database, feed, parsedFeed.entries)
      } catch (error) {
        feed.lastError = error instanceof Error ? error.message : "刷新失败"
      }
    }

    return buildFeedView(database)
  })
}

export async function setEntryRead(input: { entryId: string; read: boolean }) {
  return withWritableDatabase(async (database) => {
    const entry = database.entries.find((item) => item.id === input.entryId)
    if (!entry) {
      throw new Error("内容不存在")
    }

    entry.read = input.read
    return entry
  })
}

export async function setEntryStarred(input: { entryId: string; starred: boolean }) {
  return withWritableDatabase(async (database) => {
    const entry = database.entries.find((item) => item.id === input.entryId)
    if (!entry) {
      throw new Error("内容不存在")
    }

    entry.starred = input.starred
    return entry
  })
}

export async function markAllAsRead(query: TimelineQuery = {}) {
  return withWritableDatabase(async (database) => {
    const timelineEntries = buildTimelineEntries(database, query)
    const ids = new Set(timelineEntries.map((entry) => entry.id))

    for (const entry of database.entries) {
      if (ids.has(entry.id)) {
        entry.read = true
      }
    }

    return { success: true, count: ids.size }
  })
}

export async function updateSettings(input: Partial<LocalReaderSettings>) {
  return withWritableDatabase(async (database) => {
    database.settings = {
      ...database.settings,
      ...input,
      language: "zh-CN",
      refreshIntervalMinutes: Math.max(
        5,
        Math.min(720, input.refreshIntervalMinutes ?? database.settings.refreshIntervalMinutes),
      ),
    }

    return database.settings
  }).finally(() => updateRefreshTimer())
}
