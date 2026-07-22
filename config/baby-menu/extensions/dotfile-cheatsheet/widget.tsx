import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { DotfileCheatsheetView } from "./components";

export const dotfileCheatsheetWidget: RefreshableBabyMenuWidget = {
  id: "dotfile-cheatsheet",
  title: "DOTFILE · CHEATSHEET",
  render: () => <DotfileCheatsheetView />,
};
