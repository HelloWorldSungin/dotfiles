import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { CodexQuotaView } from "./components";
import { refreshCodexQuota } from "./store";

export const codexQuotaWidget: RefreshableBabyMenuWidget = {
  id: "codex-quota",
  title: "CODEX · WEEKLY",
  viewRefreshIntervalMs: 5 * 60 * 1_000,
  refreshView: refreshCodexQuota,
  render: () => <CodexQuotaView />,
};
