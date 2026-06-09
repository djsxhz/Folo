import { mkdtemp, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "pathe"

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

const mocks = vi.hoisted(() => ({
  userDataDir: "",
}))

vi.mock("electron", () => ({
  app: {
    getPath: vi.fn(() => mocks.userDataDir),
  },
}))

import { getTimeline, setEntryRead } from "./engine"

const databaseFilePath = () => path.join(mocks.userDataDir, "local-reader", "database.json")

describe("local-reader engine persistence", () => {
  beforeEach(async () => {
    mocks.userDataDir = await mkdtemp(path.join(tmpdir(), "folo-local-reader-"))
  })

  afterEach(async () => {
    await rm(mocks.userDataDir, { recursive: true, force: true })
  })

  it("persists concurrent read-state updates without losing entries", async () => {
    await readFile(databaseFilePath()).catch(async () => {
      const initialDatabase = {
        feeds: [
          {
            id: "feed-1",
            title: "Feed 1",
            url: "https://example.com/feed.xml",
            siteUrl: "https://example.com",
            description: null,
            imageUrl: null,
            category: null,
            view: 0,
            createdAt: Date.now(),
            lastFetchedAt: null,
            lastError: null,
          },
        ],
        entries: [
          {
            id: "entry-1",
            guid: "guid-1",
            feedId: "feed-1",
            title: "Entry 1",
            url: null,
            author: null,
            excerpt: null,
            contentHtml: null,
            publishedAt: Date.now(),
            createdAt: Date.now(),
            read: false,
            starred: false,
            kind: "article",
            thumbnailUrl: null,
            embedUrl: null,
            videoUrl: null,
            attachments: [],
          },
          {
            id: "entry-2",
            guid: "guid-2",
            feedId: "feed-1",
            title: "Entry 2",
            url: null,
            author: null,
            excerpt: null,
            contentHtml: null,
            publishedAt: Date.now(),
            createdAt: Date.now(),
            read: false,
            starred: false,
            kind: "article",
            thumbnailUrl: null,
            embedUrl: null,
            videoUrl: null,
            attachments: [],
          },
        ],
        settings: {
          language: "zh-CN",
          refreshIntervalMinutes: 30,
        },
      }

      await vi.importActual<typeof import("node:fs/promises")>("node:fs/promises").then(
        async ({ mkdir, writeFile }) => {
          const dir = path.dirname(databaseFilePath())
          await mkdir(dir, { recursive: true })
          await writeFile(databaseFilePath(), JSON.stringify(initialDatabase), "utf8")
        },
      )
    })

    await Promise.all([
      setEntryRead({ entryId: "entry-1", read: true }),
      setEntryRead({ entryId: "entry-2", read: true }),
    ])

    const timeline = await getTimeline({ feedId: "feed-1" })
    expect(timeline).toHaveLength(2)
    expect(timeline.every((entry) => entry.read)).toBe(true)

    const persisted = JSON.parse(await readFile(databaseFilePath(), "utf8")) as {
      entries: Array<{ id: string; read: boolean }>
    }
    expect(
      persisted.entries
        .filter((entry) => entry.id === "entry-1" || entry.id === "entry-2")
        .every((entry) => entry.read),
    ).toBe(true)
  })
})
