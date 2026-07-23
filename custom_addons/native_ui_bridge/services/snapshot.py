import hashlib
import json
from datetime import datetime, timezone


class NativeUiSnapshotBuilder:
    def __init__(self, env, bridge_version, protocol_version, capabilities, odoo_version):
        self.env = env
        self.bridge_version = bridge_version
        self.protocol_version = protocol_version
        self.capabilities = capabilities
        self.odoo_version = odoo_version

    def build_index(self, menus, profile="default"):
        actions = self._collect_actions(menus)
        models = self._collect_models(actions)
        payload = {
            "manifest": {
                "snapshot_version": 1,
                "native_engine_version": self.bridge_version,
                "protocol_version": self.protocol_version,
                "odoo_version": self.odoo_version,
                "database": self.env.cr.dbname,
                "profile": profile or "default",
                "created_at": self._utc_now(),
                "required_capabilities": [
                    "session.v1",
                    "snapshot.index.v1",
                    "menus.v1",
                    "actions.v1",
                    "fields.v1",
                    "views.lazy.v1",
                    "records.paged.v1",
                    "native.ir.v1",
                ],
            },
            "menus": menus,
            "actions": actions,
            "models": models,
            "loading_policy": {
                "startup": "manifest_menus_actions_and_model_index",
                "views": "load_by_action_or_model",
                "ir": "load_by_model_and_view",
                "records": "paged",
            },
        }
        payload["manifest"]["content_hash"] = self._hash(payload)
        return payload

    def _collect_actions(self, menu_node):
        actions = {}
        self._walk_menus(menu_node, actions)
        return list(actions.values())

    def _walk_menus(self, menu_node, actions):
        action = (menu_node or {}).get("action")
        if action and action.get("id"):
            key = f"{action.get('model') or 'ir.actions.actions'}:{action['id']}"
            actions[key] = {
                "id": action["id"],
                "model": action.get("model") or "ir.actions.actions",
                "raw": action.get("raw"),
                "endpoint": action.get("endpoint"),
            }
        for child in (menu_node or {}).get("children", []):
            self._walk_menus(child, actions)

    def _collect_models(self, actions):
        models = {}
        for action in actions:
            try:
                values = self._read_action(action)
            except Exception:
                continue
            model_name = values.get("res_model")
            if not model_name:
                continue
            models[model_name] = {
                "model": model_name,
                "name": values.get("name") or model_name,
                "view_modes": self._split_view_mode(values.get("view_mode")),
                "endpoints": {
                    "fields": f"/native-ui/model/{model_name}/fields",
                    "views": f"/native-ui/model/{model_name}/views",
                    "ir": f"/native-ui/model/{model_name}/ir",
                    "onchange": f"/native-ui/model/{model_name}/onchange",
                    "records": f"/native-ui/model/{model_name}/records",
                    "schema": f"/native-ui/schema/{model_name}",
                },
            }
        return list(models.values())

    def _read_action(self, action):
        action_id = action.get("id")
        for model_name in (
            action.get("model"),
            "ir.actions.act_window",
            "ir.actions.server",
            "ir.actions.client",
            "ir.actions.report",
            "ir.actions.url",
        ):
            if not model_name or model_name not in self.env:
                continue
            record = self.env[model_name].browse(action_id)
            if record.exists():
                return record.read()[0]
        return {}

    def _split_view_mode(self, view_mode):
        return [
            "list" if item == "tree" else item
            for item in (view_mode or "").split(",")
            if item
        ]

    def _utc_now(self):
        return datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    def _hash(self, value):
        serialized = json.dumps(value, sort_keys=True, default=str).encode("utf-8")
        return hashlib.sha256(serialized).hexdigest()
