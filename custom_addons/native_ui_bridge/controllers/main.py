import hashlib
import json
import time
from datetime import date
from datetime import datetime, timezone

from odoo import http, release
from odoo.exceptions import AccessError, MissingError, UserError, ValidationError
from odoo.http import request
from odoo.tools.safe_eval import safe_eval

from ..services import NativeUiIrBuilder, NativeUiSnapshotBuilder


BRIDGE_VERSION = "1.0.0"
PROTOCOL_VERSION = 1
DEFAULT_LIMIT = 80
MAX_LIMIT = 500

CAPABILITIES = [
    "session.v1",
    "snapshot.index.v1",
    "menus.v1",
    "actions.v1",
    "fields.v1",
    "views.lazy.v1",
    "records.paged.v1",
    "schema.lazy.v1",
    "native.ir.v1",
    "snapshot.materialized.v1",
    "permissions.v1",
    "defaults.v1",
    "name_search.v1",
    "onchange.v1",
    "crud.v1",
]

FIELD_ATTRIBUTES = [
    "string",
    "type",
    "required",
    "readonly",
    "store",
    "sortable",
    "relation",
    "selection",
    "help",
    "groups",
    "company_dependent",
]


class NativeUiBridgeController(http.Controller):
    @http.route("/native-ui/health", type="json", auth="none", methods=["POST"], csrf=False)
    def health(self):
        return {
            "ok": True,
            "bridge_version": BRIDGE_VERSION,
            "protocol_version": PROTOCOL_VERSION,
            "odoo_version": release.version,
            "capabilities": CAPABILITIES,
        }

    @http.route("/native-ui/session", type="json", auth="user", methods=["POST"], csrf=False)
    def session(self):
        user = request.env.user
        return {
            "ok": True,
            "bridge_version": BRIDGE_VERSION,
            "protocol_version": PROTOCOL_VERSION,
            "odoo_version": release.version,
            "odoo_serie": getattr(release, "serie", release.version),
            "database": request.env.cr.dbname,
            "uid": user.id,
            "user": {
                "id": user.id,
                "name": user.name,
                "login": user.login,
                "lang": user.lang,
                "tz": user.tz,
                "company_id": self._many2one(user.company_id),
                "company_ids": [self._many2one(company) for company in user.company_ids],
            },
            "capabilities": CAPABILITIES,
        }

    @http.route("/native-ui/snapshot/index", type="json", auth="user", methods=["POST"], csrf=False)
    def snapshot_index(self, profile=None):
        menus = self._menu_tree()
        return self._snapshot_builder().build_index(menus, profile=profile or "default")

    @http.route("/native-ui/snapshot/materialize", type="json", auth="user", methods=["POST"], csrf=False)
    def snapshot_materialize(self, profile=None, models=None, include_ir=False):
        menus = self._menu_tree()
        snapshot = self._snapshot_builder().build_index(menus, profile=profile or "default")
        selected_models = set(models or [])

        if include_ir:
            materialized = {}
            for model_entry in snapshot.get("models", []):
                model_name = model_entry.get("model")
                if selected_models and model_name not in selected_models:
                    continue
                try:
                    materialized[model_name] = self._ir_payload(model_name).get("ir")
                except Exception as exc:
                    materialized[model_name] = {
                        "error": str(exc),
                        "model": model_name,
                    }
            snapshot["materialized_ir"] = materialized

        snapshot["manifest"]["materialized_at"] = self._utc_now()
        snapshot["manifest"]["content_hash"] = self._hash(snapshot)
        return snapshot

    @http.route("/native-ui/apps", type="json", auth="user", methods=["POST"], csrf=False)
    def apps(self):
        root = self._menu_tree()
        apps = [
            child
            for child in root.get("children", [])
            if child.get("children") or child.get("action")
        ]
        return {"count": len(apps), "apps": apps}

    @http.route("/native-ui/menus", type="json", auth="user", methods=["POST"], csrf=False)
    def menus(self):
        root = self._menu_tree()
        return {"root": root, "count": self._count_menus(root)}

    @http.route("/native-ui/action/<int:action_id>", type="json", auth="user", methods=["POST"], csrf=False)
    def action(self, action_id):
        return self._read_action(("ir.actions.actions", action_id))

    @http.route("/native-ui/action", type="json", auth="user", methods=["POST"], csrf=False)
    def action_by_ref(self, action_ref=None, action_id=None):
        ref = action_ref or action_id
        return self._read_action(ref)

    @http.route("/native-ui/model/<string:model_name>/fields", type="json", auth="user", methods=["POST"], csrf=False)
    def model_fields(self, model_name, fields=None, attributes=None):
        return self._fields_payload(model_name, fields=fields, attributes=attributes)

    @http.route("/native-ui/model/<string:model_name>/views", type="json", auth="user", methods=["POST"], csrf=False)
    def model_views(self, model_name, views=None, options=None):
        return self._views_payload(model_name, views=views, options=options)

    @http.route("/native-ui/model/<string:model_name>/ir", type="json", auth="user", methods=["POST"], csrf=False)
    def model_ir(self, model_name, views=None, options=None):
        return self._ir_payload(model_name, views=views, options=options)

    @http.route("/native-ui/model/<string:model_name>/permissions", type="json", auth="user", methods=["POST"], csrf=False)
    def model_permissions(self, model_name):
        Model = self._model(model_name)
        permissions = {}
        for operation in ("read", "write", "create", "unlink"):
            permissions[operation] = self._has_access(Model, operation)
        return {
            "model": model_name,
            "permissions": permissions,
        }

    @http.route("/native-ui/model/<string:model_name>/defaults", type="json", auth="user", methods=["POST"], csrf=False)
    def model_defaults(self, model_name, fields=None):
        Model = self._model(model_name)
        self._check_access(Model, "create")
        requested_fields = fields or list(Model.fields_get().keys())
        return {
            "model": model_name,
            "values": Model.default_get(requested_fields),
        }

    @http.route("/native-ui/model/<string:model_name>/name-search", type="json", auth="user", methods=["POST"], csrf=False)
    def model_name_search(self, model_name, name="", domain=None, operator="ilike", limit=20):
        Model = self._model(model_name)
        self._check_access(Model, "read")
        bounded_limit = min(self._bounded_limit(limit), 80)
        matches = Model.name_search(
            name=name or "",
            args=self._sanitize_domain(domain or []),
            operator=operator or "ilike",
            limit=bounded_limit,
        )
        return {
            "model": model_name,
            "limit": bounded_limit,
            "matches": [
                {"id": record_id, "display_name": display_name}
                for record_id, display_name in matches
            ],
        }

    @http.route("/native-ui/model/<string:model_name>/onchange", type="json", auth="user", methods=["POST"], csrf=False)
    def model_onchange(self, model_name, values=None, field_names=None, fields_spec=None):
        Model = self._model(model_name)
        self._check_access(Model, "write")
        if not hasattr(Model, "onchange"):
            raise UserError(f"Model does not expose onchange: {model_name}")
        return {
            "model": model_name,
            "result": Model.onchange(
                values or {},
                field_names or [],
                fields_spec or {},
            ),
        }

    @http.route("/native-ui/model/<string:model_name>/records", type="json", auth="user", methods=["POST"], csrf=False)
    def model_records(
        self,
        model_name,
        domain=None,
        fields=None,
        offset=0,
        limit=DEFAULT_LIMIT,
        order=None,
        count=False,
    ):
        Model = self._model(model_name)
        self._check_access(Model, "read")
        domain = self._sanitize_domain(domain or [])
        offset = self._to_non_negative_int(offset)
        limit = self._bounded_limit(limit)
        order = self._safe_order(Model, order)

        records = Model.search_read(
            domain=domain,
            fields=fields or None,
            offset=offset,
            limit=limit,
            order=order,
        )
        result = {
            "model": model_name,
            "offset": offset,
            "limit": limit,
            "count": len(records),
            "records": records,
        }
        if count:
            result["total"] = Model.search_count(domain)
        return result

    @http.route("/native-ui/model/<string:model_name>/record/<int:record_id>", type="json", auth="user", methods=["POST"], csrf=False)
    def record_read(self, model_name, record_id, fields=None):
        Model = self._model(model_name)
        self._check_access(Model, "read")
        record = Model.browse(record_id)
        if not record.exists():
            raise MissingError(f"Record not found: {model_name},{record_id}")
        record.check_access_rule("read")
        return {
            "model": model_name,
            "id": record_id,
            "record": record.read(fields or None)[0],
        }

    @http.route("/native-ui/model/<string:model_name>/create", type="json", auth="user", methods=["POST"], csrf=False)
    def record_create(self, model_name, values=None):
        Model = self._model(model_name)
        self._check_access(Model, "create")
        record = Model.create(values or {})
        return {
            "model": model_name,
            "id": record.id,
            "display_name": record.display_name,
        }

    @http.route("/native-ui/model/<string:model_name>/write", type="json", auth="user", methods=["POST"], csrf=False)
    def record_write(self, model_name, ids=None, values=None):
        Model = self._model(model_name)
        self._check_access(Model, "write")
        record_ids = self._normalize_ids(ids)
        records = Model.browse(record_ids)
        if len(records.exists()) != len(record_ids):
            raise MissingError(f"Some records were not found in {model_name}.")
        records.check_access_rule("write")
        records.write(values or {})
        return {
            "model": model_name,
            "ids": record_ids,
            "updated": True,
        }

    @http.route("/native-ui/model/<string:model_name>/unlink", type="json", auth="user", methods=["POST"], csrf=False)
    def record_unlink(self, model_name, ids=None):
        Model = self._model(model_name)
        self._check_access(Model, "unlink")
        record_ids = self._normalize_ids(ids)
        records = Model.browse(record_ids)
        if len(records.exists()) != len(record_ids):
            raise MissingError(f"Some records were not found in {model_name}.")
        records.check_access_rule("unlink")
        records.unlink()
        return {
            "model": model_name,
            "ids": record_ids,
            "deleted": True,
        }

    @http.route("/native-ui/schema/<string:model_name>", type="json", auth="user", methods=["POST"], csrf=False)
    def schema(self, model_name, fields=None, views=None, options=None):
        return {
            "model": model_name,
            "fields": self._fields_payload(model_name, fields=fields)["fields"],
            "views": self._views_payload(model_name, views=views, options=options)["views"],
            "ir": self._ir_payload(model_name, views=views, options=options)["ir"],
            "loading_policy": {
                "records_endpoint": f"/native-ui/model/{model_name}/records",
                "ir_endpoint": f"/native-ui/model/{model_name}/ir",
                "default_limit": DEFAULT_LIMIT,
                "max_limit": MAX_LIMIT,
            },
        }

    def _model(self, model_name):
        if model_name not in request.env:
            raise UserError(f"Unknown Odoo model: {model_name}")
        return request.env[model_name]

    def _fields_payload(self, model_name, fields=None, attributes=None):
        Model = self._model(model_name)
        self._check_access(Model, "read")
        requested_attributes = attributes or FIELD_ATTRIBUTES
        field_meta = Model.fields_get(
            allfields=fields or None,
            attributes=requested_attributes,
        )
        return {
            "model": model_name,
            "field_count": len(field_meta),
            "fields": field_meta,
        }

    def _views_payload(self, model_name, views=None, options=None):
        Model = self._model(model_name)
        self._check_access(Model, "read")
        requested_views = self._normalize_views(views)
        requested_options = options or {
            "toolbar": False,
            "load_filters": False,
        }

        try:
            payload = Model.get_views(requested_views, options=requested_options)
        except AttributeError:
            payload = self._legacy_views_payload(Model, requested_views, requested_options)
        except (AccessError, MissingError, UserError, ValidationError):
            raise
        except Exception:
            payload = Model.get_views(
                self._fallback_tree_views(requested_views),
                options=requested_options,
            )

        return {
            "model": model_name,
            "views": payload.get("views", {}),
            "fields": payload.get("fields", {}),
        }

    def _ir_payload(self, model_name, views=None, options=None):
        views_payload = self._views_payload(model_name, views=views, options=options)
        ir = NativeUiIrBuilder().build_documents(model_name, views_payload)
        return {
            "model": model_name,
            "ir": ir,
            "ir_count": len(ir),
        }

    def _legacy_views_payload(self, Model, views, options):
        result = {"views": {}, "fields": {}}
        for view_id, view_type in views:
            legacy_type = "tree" if view_type == "list" else view_type
            view = Model.fields_view_get(
                view_id=view_id or None,
                view_type=legacy_type,
                toolbar=bool(options.get("toolbar")),
            )
            result["views"][view_type] = view
            result["fields"].update(view.get("fields", {}))
        return result

    def _normalize_views(self, views):
        if not views:
            return [(False, "list"), (False, "form"), (False, "search")]

        normalized = []
        for item in views:
            if isinstance(item, dict):
                view_id = item.get("id") or False
                view_type = item.get("type") or "form"
            else:
                view_id = item[0] if len(item) > 0 else False
                view_type = item[1] if len(item) > 1 else "form"
            normalized.append((view_id or False, "list" if view_type == "tree" else view_type))
        return normalized

    def _normalize_ids(self, ids):
        if ids is None:
            raise UserError("Missing record ids.")
        if isinstance(ids, int):
            return [ids]
        if isinstance(ids, str) and ids.isdigit():
            return [int(ids)]
        if isinstance(ids, (list, tuple)):
            record_ids = []
            for value in ids:
                try:
                    record_ids.append(int(value))
                except (TypeError, ValueError):
                    raise UserError(f"Invalid record id: {value}")
            if not record_ids:
                raise UserError("Missing record ids.")
            return record_ids
        raise UserError("Invalid record ids.")

    def _safe_order(self, Model, order):
        if not order:
            return None

        valid_terms = []
        for raw_term in str(order).split(","):
            parts = raw_term.strip().split()
            if not parts:
                continue
            field_name = parts[0]
            direction = parts[1].lower() if len(parts) > 1 else ""
            field = getattr(Model, "_fields", {}).get(field_name)
            if not field or not getattr(field, "store", False):
                continue
            if direction not in ("", "asc", "desc"):
                direction = ""
            valid_terms.append(" ".join(part for part in (field_name, direction) if part))

        if valid_terms:
            return ", ".join(valid_terms)
        if "name" in getattr(Model, "_fields", {}) and getattr(Model._fields["name"], "store", False):
            return "name"
        return "id"

    def _fallback_tree_views(self, views):
        return [
            (view_id, "tree" if view_type == "list" else view_type)
            for view_id, view_type in views
        ]

    def _menu_tree(self):
        menu_model = request.env["ir.ui.menu"]
        try:
            raw = menu_model.load_menus(getattr(request.session, "debug", False))
        except TypeError:
            raw = menu_model.load_menus(False)

        root = raw.get("root", raw) if isinstance(raw, dict) else raw
        menu_index = raw if isinstance(raw, dict) else {}
        return self._normalize_menu(root, menu_index=menu_index)

    def _normalize_menu(self, node, menu_index=None):
        menu_index = menu_index or {}
        if isinstance(node, int):
            node = menu_index.get(node) or {}
        if not isinstance(node, dict):
            return {
                "id": False,
                "name": "",
                "xmlid": "",
                "action": None,
                "children": [],
            }
        children = node.get("children") or []
        return {
            "id": node.get("id") or False,
            "name": node.get("name") or "",
            "xmlid": node.get("xmlid") or "",
            "action": self._normalize_action_ref(node.get("action")),
            "children": [
                self._normalize_menu(child, menu_index=menu_index)
                for child in children
            ],
        }

    def _normalize_action_ref(self, action):
        if not action:
            return None
        if isinstance(action, str) and "," in action:
            action_model, action_id = action.split(",", 1)
            try:
                parsed_id = int(action_id)
            except (TypeError, ValueError):
                return {"model": action_model, "raw": action}
            return {
                "model": action_model,
                "id": parsed_id,
                "raw": action,
                "endpoint": f"/native-ui/action/{parsed_id}",
            }
        if isinstance(action, int):
            return {
                "model": "ir.actions.actions",
                "id": action,
                "raw": action,
                "endpoint": f"/native-ui/action/{action}",
            }
        return {"raw": action}

    def _read_action(self, ref):
        action_model, action_id = self._parse_action_ref(ref)
        if not action_id:
            raise UserError("Missing action id.")

        candidates = []
        if action_model and action_model in request.env and action_model != "ir.actions.actions":
            candidates.append(action_model)
        candidates.extend(
            [
                "ir.actions.act_window",
                "ir.actions.server",
                "ir.actions.client",
                "ir.actions.report",
                "ir.actions.act_url",
            ]
        )
        if action_model == "ir.actions.actions":
            candidates.append("ir.actions.actions")

        seen = set()
        for model_name in candidates:
            if model_name in seen or model_name not in request.env:
                continue
            seen.add(model_name)
            record = request.env[model_name].browse(action_id)
            if not record.exists():
                continue
            self._check_access(record, "read")
            values = record.read()[0]
            values["endpoint"] = f"/native-ui/action/{action_id}"
            if "domain" in values:
                values["domain_native"] = self._safe_eval_action_expr(
                    values.get("domain"),
                    default=[],
                )
            if "context" in values:
                values["context_native"] = self._safe_eval_action_expr(
                    values.get("context"),
                    default={},
                )
            if values.get("res_model"):
                values["model_endpoints"] = {
                    "fields": f"/native-ui/model/{values['res_model']}/fields",
                    "views": f"/native-ui/model/{values['res_model']}/views",
                    "records": f"/native-ui/model/{values['res_model']}/records",
                    "schema": f"/native-ui/schema/{values['res_model']}",
                }
            return values

        raise MissingError(f"Action not found: {ref}")

    def _safe_eval_action_expr(self, expression, default):
        if expression in (None, False, ""):
            return default
        if isinstance(expression, (list, tuple, dict)):
            return self._json_compatible(expression)
        if not isinstance(expression, str):
            return default

        safe_globals = {
            "uid": request.uid,
            "user": request.env.user,
            "context": dict(request.env.context),
            "time": time,
            "datetime": datetime,
            "date": date,
            "true": True,
            "false": False,
            "null": None,
        }
        try:
            return self._json_compatible(safe_eval(expression, safe_globals))
        except Exception:
            return None

    def _sanitize_domain(self, domain):
        if not domain or not isinstance(domain, (list, tuple)):
            return []

        sanitized = []
        for token in domain:
            if token in (None, False):
                continue
            if isinstance(token, tuple):
                token = list(token)
            if isinstance(token, list):
                if not token:
                    continue
                sanitized.append(self._json_compatible(token))
                continue
            if token in ("&", "|", "!"):
                sanitized.append(token)
        return sanitized

    def _json_compatible(self, value):
        if isinstance(value, tuple):
            return [self._json_compatible(item) for item in value]
        if isinstance(value, list):
            return [self._json_compatible(item) for item in value]
        if isinstance(value, dict):
            return {
                str(key): self._json_compatible(item)
                for key, item in value.items()
                if isinstance(key, (str, int, float, bool))
            }
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        return str(value)

    def _parse_action_ref(self, ref):
        if isinstance(ref, int):
            return "ir.actions.actions", ref
        if isinstance(ref, str) and "," in ref:
            model_name, action_id = ref.split(",", 1)
            try:
                return model_name, int(action_id)
            except (TypeError, ValueError):
                return model_name, 0
        if isinstance(ref, str) and ref.isdigit():
            return "ir.actions.actions", int(ref)
        if isinstance(ref, dict):
            return ref.get("model") or "ir.actions.actions", int(ref.get("id") or 0)
        return "ir.actions.actions", 0

    def _bounded_limit(self, value):
        parsed = self._to_non_negative_int(value)
        if parsed <= 0:
            return DEFAULT_LIMIT
        return min(parsed, MAX_LIMIT)

    def _to_non_negative_int(self, value):
        try:
            return max(0, int(value))
        except (TypeError, ValueError):
            return 0

    def _check_access(self, recordset, operation):
        if hasattr(recordset, "check_access"):
            return recordset.check_access(operation)
        return recordset.check_access_rights(operation)

    def _has_access(self, recordset, operation):
        try:
            self._check_access(recordset, operation)
            return True
        except AccessError:
            return False

    def _many2one(self, record):
        if not record:
            return None
        return {"id": record.id, "display_name": record.display_name}

    def _count_menus(self, node):
        return 1 + sum(self._count_menus(child) for child in node.get("children", []))

    def _utc_now(self):
        return datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    def _hash(self, value):
        serialized = json.dumps(value, sort_keys=True, default=str).encode("utf-8")
        return hashlib.sha256(serialized).hexdigest()

    def _snapshot_builder(self):
        return NativeUiSnapshotBuilder(
            request.env,
            BRIDGE_VERSION,
            PROTOCOL_VERSION,
            CAPABILITIES,
            release.version,
        )
