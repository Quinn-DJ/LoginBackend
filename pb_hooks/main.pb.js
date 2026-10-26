/// <reference path="../pb_data/types.d.ts" />

onRecordCreateRequest(
  (e) => {
    if (e.auth && e.auth.collection().name === "users") {
      e.record.set("owner", e.auth.id);
    }
    e.next();
  },
  "places"
);

onRecordUpdateRequest(
  (e) => {
    if (e.auth && e.auth.collection().name === "users") {
      const originalOwner = e.record.original().getString("owner");
      const requestedOwner = e.record.getString("owner");

      if (!originalOwner || requestedOwner !== originalOwner) {
        throw new ForbiddenError("Place ownership cannot be changed");
      }
      if (e.auth.id !== originalOwner) {
        throw new ForbiddenError("Place ownership does not match the current user");
      }

      e.record.set("owner", originalOwner);
    }
    e.next();
  },
  "places"
);
