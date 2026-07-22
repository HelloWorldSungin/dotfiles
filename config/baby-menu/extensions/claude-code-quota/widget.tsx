import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { ClaudeQuotaView } from "./components";
import { refreshClaudeQuota } from "./store";

export const claudeCodeQuotaWidget: RefreshableBabyMenuWidget = {
  id: "claude-code-quota",
  title: "CLAUDE · QUOTA",
  viewRefreshIntervalMs: 5 * 60 * 1000,
  refreshView: refreshClaudeQuota,
  render: () => <ClaudeQuotaView />,
};
