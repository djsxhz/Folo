import type { LexicalRichEditorRef } from "@follow/components/ui/lexical-rich-editor/types.js"
import type { PrimitiveAtom } from "jotai"
import { createContext, use } from "react"
import type { StoreApi } from "zustand"
import type { UseBoundStoreWithEqualityFn } from "zustand/traditional"

import { createAIChatStore } from "./store"
import type { AiChatStore } from "./store"

export type AIPanelRefs = {
  inputRef: React.RefObject<LexicalRichEditorRef>
}

export const AIPanelRefsContext = createContext<AIPanelRefs>(null!)

export const AIChatStoreContext = createContext<UseBoundStoreWithEqualityFn<StoreApi<AiChatStore>>>(
  null!,
)

const fallbackAIChatStore = createAIChatStore()

export const useAIChatStore = () => {
  const store = use(AIChatStoreContext)
  if (!store) {
    if (import.meta.env.DEV) {
      console.warn("useAIChatStore is using the fallback store because no AIChatStoreContext exists")
    }
    return fallbackAIChatStore
  }
  return store
}

export type AIRootStateContext = {
  isScrolledBeyondThreshold: PrimitiveAtom<boolean>
}

export const AIRootStateContext = createContext<AIRootStateContext>(null!)

export const useAIRootState = () => {
  const context = use(AIRootStateContext)
  if (!context) {
    throw new Error("useAIRootState must be used within a AIRootStateContext")
  }
  return context
}
