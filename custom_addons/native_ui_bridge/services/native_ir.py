import xml.etree.ElementTree as ET


NODE_TYPES = {
    "form": "Form",
    "list": "List",
    "tree": "List",
    "search": "Search",
    "sheet": "Section",
    "group": "Group",
    "notebook": "Notebook",
    "page": "Tab",
    "field": "Field",
    "label": "Label",
    "button": "Button",
    "separator": "Separator",
    "newline": "Spacer",
    "header": "Header",
    "footer": "Footer",
    "div": "Section",
    "span": "Label",
}

NODE_ATTRIBUTE_ALLOWLIST = {
    "name",
    "string",
    "type",
    "widget",
    "readonly",
    "invisible",
    "required",
    "domain",
    "context",
    "groups",
    "attrs",
    "modifiers",
    "placeholder",
    "help",
    "class",
    "col",
    "colspan",
    "nolabel",
    "sum",
    "decoration-danger",
    "decoration-info",
    "decoration-muted",
    "decoration-primary",
    "decoration-success",
    "decoration-warning",
}

UNSUPPORTED_WIDGETS = {
    "ace",
    "html",
    "iframe",
    "mail_thread",
    "mail_activity",
    "kanban_activity",
    "web_ribbon",
}


class NativeUiIrBuilder:
    def build_document(self, model_name, view_type, view_payload, field_meta=None):
        arch = (view_payload or {}).get("arch") or ""
        fields = field_meta or (view_payload or {}).get("fields") or {}
        root_node = self._parse_arch(arch)
        unsupported = []

        if root_node is None:
            return {
                "ir_version": 1,
                "model": model_name,
                "view_type": view_type,
                "root": {
                    "type": self._default_root_type(view_type),
                    "properties": {},
                    "children": [],
                },
                "fields": self._compact_fields(fields),
                "unsupported": [
                    {
                        "feature": "view.arch",
                        "reason": "missing_or_invalid_arch",
                        "view_type": view_type,
                    }
                ],
            }

        root = self._node_to_ir(root_node, fields, unsupported)
        return {
            "ir_version": 1,
            "model": model_name,
            "view_type": "list" if view_type == "tree" else view_type,
            "root": root,
            "fields": self._compact_fields(fields),
            "unsupported": unsupported,
        }

    def build_documents(self, model_name, views_payload):
        result = {}
        views = (views_payload or {}).get("views") or {}
        shared_fields = (views_payload or {}).get("fields") or {}
        for view_type, view_payload in views.items():
            normalized_type = "list" if view_type == "tree" else view_type
            result[normalized_type] = self.build_document(
                model_name,
                normalized_type,
                view_payload,
                field_meta=(view_payload or {}).get("fields") or shared_fields,
            )
        return result

    def _parse_arch(self, arch):
        if not arch:
            return None
        try:
            return ET.fromstring(arch)
        except ET.ParseError:
            return None

    def _node_to_ir(self, element, fields, unsupported):
        tag = self._strip_namespace(element.tag)
        node_type = NODE_TYPES.get(tag, "Container")
        properties = {
            key: value
            for key, value in element.attrib.items()
            if key in NODE_ATTRIBUTE_ALLOWLIST
        }

        field_name = properties.get("name") if tag == "field" else None
        if field_name and field_name in fields:
            properties["field_type"] = fields[field_name].get("type")
            if fields[field_name].get("relation"):
                properties["relation"] = fields[field_name].get("relation")

        widget = properties.get("widget")
        if widget in UNSUPPORTED_WIDGETS:
            unsupported.append(
                {
                    "feature": "widget",
                    "widget": widget,
                    "node": tag,
                    "field": field_name,
                    "reason": "requires_native_renderer",
                }
            )

        text = (element.text or "").strip()
        if text and node_type in ("Label", "Separator"):
            properties["text"] = text

        children = [
            self._node_to_ir(child, fields, unsupported)
            for child in list(element)
            if isinstance(child.tag, str)
        ]

        node = {
            "type": node_type,
            "tag": tag,
            "properties": properties,
            "children": children,
        }
        if field_name:
            node["id"] = field_name
        elif properties.get("name"):
            node["id"] = properties["name"]
        return node

    def _compact_fields(self, fields):
        compact = {}
        for name, meta in (fields or {}).items():
            compact[name] = {
                key: value
                for key, value in meta.items()
                if key
                in (
                    "string",
                    "type",
                    "required",
                    "readonly",
                    "relation",
                    "selection",
                    "help",
                )
            }
        return compact

    def _default_root_type(self, view_type):
        return {
            "form": "Form",
            "list": "List",
            "tree": "List",
            "search": "Search",
        }.get(view_type, "View")

    def _strip_namespace(self, tag):
        if "}" in tag:
            return tag.rsplit("}", 1)[-1]
        return tag
