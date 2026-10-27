/// <reference path="../pb_data/types.d.ts" />

migrate(
  (app) => {
    const settings = app.settings();
    settings.trustedProxy.headers = ["X-Forwarded-For"];
    settings.trustedProxy.useLeftmostIP = false;
    app.save(settings);

    const users = app.findCollectionByNameOrId("users");
    users.listRule = "id = @request.auth.id";
    users.viewRule = "id = @request.auth.id";
    users.createRule = null;
    users.updateRule = "id = @request.auth.id";
    users.deleteRule = null;
    users.authRule = "verified = true";
    users.passwordAuth.enabled = true;
    users.passwordAuth.identityFields = ["email"];
    users.fields.add(
      new TextField({
        name: "name",
        required: true,
        min: 1,
        max: 80,
      })
    );
    app.save(users);

    const places = new Collection({
      type: "base",
      name: "places",
      listRule: "@request.auth.id != '' && owner = @request.auth.id",
      viewRule: "@request.auth.id != '' && owner = @request.auth.id",
      createRule: "@request.auth.id != '' && owner = @request.auth.id",
      updateRule: "@request.auth.id != '' && owner = @request.auth.id",
      deleteRule: null,
      fields: [
        {
          type: "autodate",
          name: "created",
          system: true,
          onCreate: true,
          onUpdate: false,
        },
        {
          type: "autodate",
          name: "updated",
          system: true,
          onCreate: true,
          onUpdate: true,
        },
        {
          type: "relation",
          name: "owner",
          required: true,
          collectionId: users.id,
          cascadeDelete: true,
          minSelect: 1,
          maxSelect: 1,
        },
        {
          type: "text",
          name: "client_id",
          required: true,
          min: 1,
          max: 64,
        },
        {
          type: "text",
          name: "name",
          required: true,
          min: 1,
          max: 200,
        },
        {
          type: "text",
          name: "address",
          required: false,
          max: 500,
        },
        {
          type: "number",
          name: "latitude",
          required: true,
          min: -90,
          max: 90,
        },
        {
          type: "number",
          name: "longitude",
          required: true,
          min: -180,
          max: 180,
        },
        {
          type: "text",
          name: "category",
          required: false,
          max: 80,
        },
        {
          type: "json",
          name: "tags",
          required: false,
          maxSize: 4096,
        },
        {
          type: "text",
          name: "note",
          required: false,
          max: 5000,
        },
        {
          type: "select",
          name: "status",
          required: true,
          maxSelect: 1,
          values: ["want_to_go", "visited", "favorite"],
        },
        {
          type: "number",
          name: "rating",
          required: false,
          min: 0,
          max: 5,
        },
        {
          type: "date",
          name: "client_updated_at",
          required: true,
        },
        {
          type: "bool",
          name: "deleted",
          required: false,
        },
        {
          type: "text",
          name: "last_device_id",
          required: false,
          max: 100,
        },
      ],
      indexes: [
        "CREATE UNIQUE INDEX idx_places_owner_client_id ON places (owner, client_id)",
      ],
    });
    app.save(places);
  },
  (app) => {
    const places = app.findCollectionByNameOrId("places");
    app.delete(places);

    const users = app.findCollectionByNameOrId("users");
    users.fields.removeByName("name");
    users.listRule = "id = @request.auth.id";
    users.viewRule = "id = @request.auth.id";
    users.createRule = "";
    users.updateRule = "id = @request.auth.id";
    users.deleteRule = "id = @request.auth.id";
    users.authRule = "";
    app.save(users);

    const settings = app.settings();
    settings.trustedProxy.headers = [];
    settings.trustedProxy.useLeftmostIP = false;
    app.save(settings);
  }
);
