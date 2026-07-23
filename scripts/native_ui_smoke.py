from odoo.addons.native_ui_bridge.controllers.main import NativeUiBridgeController


class _RequestProxy:
    def __init__(self, env):
        self.env = env
        self.session = type("Session", (), {"debug": False})()


def run_smoke(env):
    controller = NativeUiBridgeController()

    import odoo.addons.native_ui_bridge.controllers.main as main

    original_request = main.request
    try:
        main.request = _RequestProxy(env)

        menus = controller._menu_tree()
        snapshot = controller._snapshot_builder().build_index(menus)
        fields = controller._fields_payload(
            "res.partner",
            fields=["name", "email", "phone", "company_id"],
        )
        ir = controller._ir_payload(
            "res.partner",
            views=[{"type": "form"}, {"type": "list"}],
        )
        records = env["res.partner"].search_read(
            domain=[],
            fields=["display_name"],
            limit=5,
        )
        onchange = controller.model_onchange(
            "res.partner",
            values={"name": "Native UI Smoke"},
            field_names=["name"],
            fields_spec={},
        )
    finally:
        main.request = original_request

    print("Native UI smoke OK")
    print(f"menus={controller._count_menus(menus)}")
    print(f"snapshot_models={len(snapshot.get('models', []))}")
    print(f"res_partner_fields={fields['field_count']}")
    print(f"res_partner_ir={','.join(sorted(ir['ir'].keys()))}")
    print(f"res_partner_records={len(records)}")
    print(f"res_partner_onchange={'result' in onchange}")


run_smoke(env)
