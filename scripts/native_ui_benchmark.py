import statistics
import time

from odoo.addons.native_ui_bridge.controllers.main import NativeUiBridgeController


class _RequestProxy:
    def __init__(self, env):
        self.env = env
        self.session = type("Session", (), {"debug": False})()


def measure(label, repeats, callback):
    values = []
    last = None
    for _ in range(repeats):
        start = time.perf_counter()
        last = callback()
        values.append((time.perf_counter() - start) * 1000)
    print(
        f"{label}: min={min(values):.2f}ms "
        f"median={statistics.median(values):.2f}ms "
        f"max={max(values):.2f}ms"
    )
    return last


def run_benchmark(env):
    controller = NativeUiBridgeController()

    import odoo.addons.native_ui_bridge.controllers.main as main

    original_request = main.request
    try:
        main.request = _RequestProxy(env)
        measure("menus", 5, controller._menu_tree)
        menus = controller._menu_tree()
        measure("snapshot_index", 5, lambda: controller._snapshot_builder().build_index(menus))
        measure(
            "res.partner fields",
            5,
            lambda: controller._fields_payload(
                "res.partner",
                fields=["name", "email", "phone", "company_id"],
            ),
        )
        measure(
            "res.partner ir",
            5,
            lambda: controller._ir_payload(
                "res.partner",
                views=[{"type": "form"}, {"type": "list"}],
            ),
        )
        measure(
            "res.partner records limit 80",
            5,
            lambda: controller.model_records(
                "res.partner",
                fields=["display_name"],
                limit=80,
            ),
        )
    finally:
        main.request = original_request


run_benchmark(env)
