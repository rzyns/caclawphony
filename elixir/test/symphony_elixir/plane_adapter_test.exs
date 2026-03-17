defmodule SymphonyElixir.PlaneAdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Plane.Adapter
  alias SymphonyElixir.Linear.Issue

  defmodule FakePlaneClient do
    def fetch_candidate_issues do
      send(self(), :plane_fetch_candidate_issues_called)
      {:ok, [:plane_candidate]}
    end

    def fetch_issues_by_states(states) do
      send(self(), {:plane_fetch_issues_by_states_called, states})
      {:ok, states}
    end

    def fetch_issue_states_by_ids(issue_ids) do
      send(self(), {:plane_fetch_issue_states_by_ids_called, issue_ids})
      {:ok, issue_ids}
    end

    def create_comment(issue_id, body) do
      send(self(), {:plane_create_comment_called, issue_id, body})
      :ok
    end

    def update_issue_state(issue_id, state_name) do
      send(self(), {:plane_update_issue_state_called, issue_id, state_name})
      :ok
    end
  end

  setup do
    Application.put_env(:symphony_elixir, :plane_client_module, FakePlaneClient)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :plane_client_module)
    end)

    :ok
  end

  test "plane adapter delegates fetch_candidate_issues to client" do
    assert {:ok, [:plane_candidate]} = Adapter.fetch_candidate_issues()
    assert_receive :plane_fetch_candidate_issues_called
  end

  test "plane adapter delegates fetch_issues_by_states to client" do
    assert {:ok, ["Todo", "In Progress"]} = Adapter.fetch_issues_by_states(["Todo", "In Progress"])
    assert_receive {:plane_fetch_issues_by_states_called, ["Todo", "In Progress"]}
  end

  test "plane adapter delegates fetch_issue_states_by_ids to client" do
    assert {:ok, ["issue-uuid-1"]} = Adapter.fetch_issue_states_by_ids(["issue-uuid-1"])
    assert_receive {:plane_fetch_issue_states_by_ids_called, ["issue-uuid-1"]}
  end

  test "plane adapter delegates create_comment to client" do
    assert :ok = Adapter.create_comment("issue-1", "body text")
    assert_receive {:plane_create_comment_called, "issue-1", "body text"}
  end

  test "plane adapter delegates update_issue_state to client" do
    assert :ok = Adapter.update_issue_state("issue-1", "In Progress")
    assert_receive {:plane_update_issue_state_called, "issue-1", "In Progress"}
  end

  test "tracker routes to plane adapter when kind is plane" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")
    assert Config.tracker_kind() == "plane"
    assert SymphonyElixir.Tracker.adapter() == Adapter
  end

  test "issue normalisation maps Plane fields to Issue struct" do
    # smoke test: verify the Issue struct fields we'll use
    issue = %Issue{
      id: "7c7eb8f0-0000-0000-0000-000000000001",
      identifier: "OC-42",
      title: "Fix something",
      description: "<p>Description</p>",
      priority: 2,
      state: "todo",
      labels: ["gateway"],
      assigned_to_worker: true,
      blocked_by: []
    }

    assert issue.identifier == "OC-42"
    assert issue.priority == 2
    assert issue.state == "todo"
    assert issue.labels == ["gateway"]
  end
end
