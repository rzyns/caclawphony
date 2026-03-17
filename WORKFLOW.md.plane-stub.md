---
tracker:
  kind: plane
  api_key: $PLANE_API_KEY
  project_slug: 7c7eb8f0-ec76-42e8-99d8-a212696395db   # openclaw project UUID
  endpoint: https://plane.svc.dziurzynscy.com/api/v1/workspaces/warsztat   # self-hosted base URL; omit for Plane.so cloud (uses plane_workspace_slug fallback)
  plane_workspace_slug: warsztat   # only needed if endpoint is not set (Plane.so cloud fallback)
  project_identifier: OC
  active_states: todo, pr_triage, review, review_complete, prepare, prepare_complete, test, pre_merge, merge, rebase, request_changes, closure
  terminal_states: done, cancelled, duplicate

states:
  backlog: 692e0def-0588-409f-87e9-e0ba99493c40
  todo: 479bb9e1-5754-4a52-b0c7-a38be870659a
  pr_triage: cd715f44-a229-44d1-9b45-bcc351d91170
  review: ecae992e-11d1-4dfa-b5cb-7967b385c455
  review_complete: 5c426d98-d3cf-468a-8900-d2328e3ed3f6
  prepare: 08d365d5-1a2d-41de-ac6f-2fe84336253d
  prepare_complete: dc6aeca2-0b16-48b0-8b37-07f43ce45a56
  test: 91849869-f51a-4379-8b67-1a25cab44e19
  pre_merge: 9ba20885-72de-477f-b6ff-31f8411ab0de
  merge: da2e49ee-23be-4b56-a3be-2eb7dcd11d76
  rebase: 09af8574-fb11-4e72-85ed-d143fd3305db
  request_changes: 2bf79991-f525-44f3-9117-cb4d257f7503
  closure: 1e61f881-8c3c-4a9d-b6a3-7d0e1197cff7
  done: dbc1eaa1-2377-444c-9d84-1f86922d2755
  cancelled: f793642e-62c3-4149-b5b2-1656ecc1dca6
  duplicate: f9715e64-cff7-49f5-9f72-db9ae83c08fa

labels:
  recommendation:
    review: db429f2d-729e-4bd2-afe6-59578146d6ee
    wait: e821c2e3-dcff-4891-8692-9780b25e3f2d
    skip: 5ebbf50c-897c-4803-8bfe-c74d07644b31
  subsystem:
    gateway: f0c2a359-0c23-46ea-8291-011fe661b8c2
    channels: aa0338e3-85ec-4aec-818d-2663e1f5ea2f
    browser: 8ccc3075-d427-4352-b8e2-0ac3686b1c0c
    agents: a63de8d5-042b-42cb-bcc5-0f12586186d6
    config: d0c46042-34a5-4cb6-8a30-7038d49a9868
    cli: c713b3a2-80f3-46e4-b713-73fef61c945d
    runtime: 72ff391d-0b6e-4828-af9e-2352a34b0d65
    auth: 9830651e-ec8c-4a83-bca8-1258621016f2
    providers: 435ff2d6-60d6-4653-8438-7e1a72c301c3
    docs: a0b41248-7283-4ece-b9c7-ed01b7f0683f
  activity:
    triaging: 672a68c1-bf63-45c8-80c9-5c89232ab095
    reviewing: 993fad3d-d66e-4fcd-b2e7-d792c5607464
    preparing: 770bb05b-7864-4700-bc3f-0f5d713d8811
    merging: 8578b1d1-62fe-4613-aeb1-4ac1feeaf817
    rebasing: 33e4e181-c22d-4978-b507-520ac4f8d7bd
    testing: 875ae0fb-e6dd-4396-bb46-281bfa9f0478
    closing: 66abde8d-80d0-4057-83e2-e2a73a1a0e33

codex:
  command: codex app-server

# TODO: Add your prompt below this line
---

TODO: Add your prompt body here.
