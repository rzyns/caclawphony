defmodule SymphonyElixir.Plane.Client do
  @moduledoc """
  Plane REST client. Normalises responses to SymphonyElixir.Linear.Issue structs.
  """

  require Logger
  alias SymphonyElixir.{Config, Linear.Issue}

  @page_size 100

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    states = Config.plane_states()
    active_names = Config.active_states()

    state_ids =
      active_names
      |> Enum.map(&Map.get(states, normalize_state_key(&1)))
      |> Enum.reject(&is_nil/1)

    case state_ids do
      [] -> {:ok, []}
      ids -> fetch_by_state_ids(ids, true)
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    states = Config.plane_states()
    normalized = Enum.map(state_names, &to_string/1) |> Enum.uniq()

    state_ids =
      normalized
      |> Enum.map(&Map.get(states, normalize_state_key(&1)))
      |> Enum.reject(&is_nil/1)

    case state_ids do
      [] -> {:ok, []}
      ids -> fetch_by_state_ids(ids, true)
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids)

    case ids do
      [] ->
        {:ok, []}

      _ ->
        results =
          Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
            case get_issue(id, false) do
              {:ok, issue} -> {:cont, {:ok, [issue | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case results do
          {:ok, issues} -> {:ok, Enum.reverse(issues)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    project_id = Config.plane_project_id()
    url = "#{Config.plane_base_url()}projects/#{project_id}/issues/#{issue_id}/comments/"
    payload = %{"comment_html" => body}

    case plane_request(:post, url, payload) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, response} -> {:error, {:plane_api_status, response.status}}
      {:error, reason} -> {:error, {:plane_api_request, reason}}
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) when is_binary(issue_id) and is_binary(state_name) do
    states = Config.plane_states()

    case Map.get(states, normalize_state_key(state_name)) do
      nil ->
        {:error, :state_not_found}

      state_id ->
        project_id = Config.plane_project_id()
        url = "#{Config.plane_base_url()}projects/#{project_id}/issues/#{issue_id}/"
        payload = %{"state" => state_id}

        case plane_request(:patch, url, payload) do
          {:ok, %{status: status}} when status in 200..299 -> :ok
          {:ok, response} -> {:error, {:plane_api_status, response.status}}
          {:error, reason} -> {:error, {:plane_api_request, reason}}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Internal – fetching
  # ---------------------------------------------------------------------------

  defp fetch_by_state_ids(state_ids, _fetch_relations) do
    project_id = Config.plane_project_id()

    state_query = Enum.map_join(state_ids, "&", fn id -> "state=#{id}" end)

    do_paginate(project_id, state_query, 0, [])
  end

  defp do_paginate(project_id, state_query, offset, acc) do
    url = "#{Config.plane_base_url()}projects/#{project_id}/issues/?#{state_query}&per_page=#{@page_size}&offset=#{offset}"

    case plane_request(:get, url) do
      {:ok, %{status: 200, body: body}} ->
        {results, has_more} = extract_page(body)

        normalized =
          results
          |> Enum.map(&normalize_issue(&1, project_id, nil))
          |> Enum.reject(&is_nil/1)

        updated_acc = normalized ++ acc

        if has_more do
          do_paginate(project_id, state_query, offset + @page_size, updated_acc)
        else
          {:ok, Enum.reverse(updated_acc)}
        end

      {:ok, response} ->
        Logger.error("Plane API list issues failed status=#{response.status}")
        {:error, {:plane_api_status, response.status}}

      {:error, reason} ->
        Logger.error("Plane API list issues failed: #{inspect(reason)}")
        {:error, {:plane_api_request, reason}}
    end
  end

  defp get_issue(issue_id, _fetch_relations) do
    project_id = Config.plane_project_id()
    url = "#{Config.plane_base_url()}projects/#{project_id}/issues/#{issue_id}/"

    case plane_request(:get, url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        issue = normalize_issue(body, project_id, nil)

        if is_nil(issue) do
          {:error, :normalization_failed}
        else
          {:ok, issue}
        end

      {:ok, response} ->
        {:error, {:plane_api_status, response.status}}

      {:error, reason} ->
        {:error, {:plane_api_request, reason}}
    end
  end

  defp extract_page(body) when is_map(body) do
    results = Map.get(body, "results", [])
    next_page = Map.get(body, "next_page_results", false)
    {results, next_page == true}
  end

  defp extract_page(body) when is_list(body), do: {body, false}
  defp extract_page(_body), do: {[], false}

  # ---------------------------------------------------------------------------
  # Internal – normalisation
  # ---------------------------------------------------------------------------

  defp normalize_issue(raw, _project_id, _fetch_relations) when is_map(raw) do
    states = Config.plane_states()
    labels = Config.plane_labels()
    project_identifier = Config.plane_project_identifier()

    states_by_id = Map.new(states, fn {name, uuid} -> {uuid, name} end)
    labels_by_id = build_labels_by_id(labels)

    # Plane CE does not expose issue-relations via REST; blocked_by unsupported
    blocked_by = []

    %Issue{
      id: raw["id"],
      identifier: build_identifier(project_identifier, raw["sequence_id"]),
      title: raw["name"],
      description: raw["description_html"],
      priority: parse_priority(raw["priority"]),
      state: Map.get(states_by_id, raw["state"]),
      labels: resolve_label_ids(raw["label_ids"] || raw["labels"], labels_by_id),
      assignee_id: nil,
      branch_name: nil,
      url: nil,
      assigned_to_worker: true,
      blocked_by: blocked_by,
      created_at: parse_datetime(raw["created_at"]),
      updated_at: parse_datetime(raw["updated_at"])
    }
  end

  defp normalize_issue(_raw, _project_id, _fetch_relations), do: nil

  defp build_identifier(nil, seq_id) when not is_nil(seq_id), do: to_string(seq_id)
  defp build_identifier(prefix, seq_id) when is_binary(prefix) and not is_nil(seq_id), do: "#{prefix}-#{seq_id}"
  defp build_identifier(_prefix, _seq_id), do: nil

  defp parse_priority("none"), do: nil
  defp parse_priority("urgent"), do: 1
  defp parse_priority("high"), do: 2
  defp parse_priority("medium"), do: 3
  defp parse_priority("low"), do: 4
  defp parse_priority(_), do: nil

  defp build_labels_by_id(labels) when is_map(labels) do
    Enum.reduce(labels, %{}, fn {_category, cat_labels}, acc ->
      case cat_labels do
        map when is_map(map) ->
          Enum.reduce(map, acc, fn {name, uuid}, a ->
            if is_binary(uuid), do: Map.put(a, uuid, name), else: a
          end)

        _ ->
          acc
      end
    end)
  end

  defp build_labels_by_id(_), do: %{}

  defp resolve_label_ids(nil, _labels_by_id), do: []

  defp resolve_label_ids(label_ids, labels_by_id) when is_list(label_ids) do
    label_ids
    |> Enum.map(&Map.get(labels_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp resolve_label_ids(_, _), do: []

  defp normalize_state_key(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(" ", "_")
  end

  defp normalize_state_key(name), do: to_string(name) |> normalize_state_key()

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  # ---------------------------------------------------------------------------
  # Internal – HTTP
  # ---------------------------------------------------------------------------

  defp plane_request(method, url, body \\ nil) do
    token = Config.plane_api_token()

    headers = [
      {"X-Api-Key", token || ""},
      {"Content-Type", "application/json"}
    ]

    opts = [headers: headers, connect_options: [timeout: 30_000]]

    result =
      case method do
        :get -> Req.get(url, opts)
        :post -> Req.post(url, Keyword.put(opts, :json, body))
        :patch -> Req.patch(url, Keyword.put(opts, :json, body))
        :delete -> Req.delete(url, opts)
      end

    result
  end
end
