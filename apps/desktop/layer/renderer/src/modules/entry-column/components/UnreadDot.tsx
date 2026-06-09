import { cn } from "@follow/utils/utils"

export const UnreadDot = ({
  visible,
  className,
  dotClassName,
}: {
  visible: boolean
  className?: string
  dotClassName?: string
}) => (
  <span aria-hidden className={cn("flex w-3 shrink-0 justify-center", className)}>
    <span
      className={cn(
        "size-2 rounded-full bg-accent transition-opacity duration-200",
        visible ? "opacity-100" : "opacity-0",
        dotClassName,
      )}
    />
  </span>
)
