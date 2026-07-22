import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { CursorQuotaView } from "./components";
import { refreshCursorQuota } from "./store";

export const cursorQuotaWidget: RefreshableBabyMenuWidget = {
  id: "cursor-quota",
  title: "CURSOR · QUOTA",
  viewRefreshIntervalMs: 5 * 60 * 1000,
  refreshView: refreshCursorQuota,
  render: () => <CursorQuotaView />,
};
