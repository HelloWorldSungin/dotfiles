import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { MiniMaxQuotaView } from "./components";
import { refreshMiniMaxQuota } from "./store";

export const miniMaxQuotaWidget: RefreshableBabyMenuWidget = {
  id: "minimax-quota",
  title: "MINIMAX · QUOTA",
  viewRefreshIntervalMs: 5 * 60 * 1_000,
  refreshView: refreshMiniMaxQuota,
  render: () => <MiniMaxQuotaView />,
};
