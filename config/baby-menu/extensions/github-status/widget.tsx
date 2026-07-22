import React, { useState, useEffect } from "react";
import type { RefreshableBabyMenuWidget, BabyMenuSettingsSection } from "@babymenu/contracts";
import { Field, Input, Button } from "@babymenu/ui";
import { GithubStatusView } from "./components";
import { refreshGithubStatus, fetchGithubUsername, saveGithubUsername } from "./store";

function GithubSettingsView() {
  const [username, setUsername] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchGithubUsername().then(setUsername);
  }, []);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    await saveGithubUsername(username);
    setSaving(false);
  };

  return (
    <form onSubmit={handleSave} className="flex flex-col gap-3 p-1">
      <Field label="github username" hint="defaults to your signed-in gh account">
        <Input
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          placeholder="github login"
        />
      </Field>
      <div className="flex justify-end mt-1">
        <Button type="submit" variant="primary" disabled={saving}>
          {saving ? "saving…" : "save"}
        </Button>
      </div>
    </form>
  );
}

export const githubStatusWidget: RefreshableBabyMenuWidget = {
  id: "github-status",
  title: "GITHUB · STATUS",
  viewRefreshIntervalMs: 5 * 60 * 1000,
  refreshView: refreshGithubStatus,
  render: () => <GithubStatusView />,
};

export const githubSettings: BabyMenuSettingsSection = {
  extensionId: "github-status",
  title: "GITHUB",
  render: () => <GithubSettingsView />,
};
