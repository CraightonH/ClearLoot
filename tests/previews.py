"""Optional browser smoke checks for the standalone illustrative previews."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import threading

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def main():
    server = ThreadingHTTPServer(
        ("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT))
    )
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f"http://127.0.0.1:{server.server_port}"
    try:
        with sync_playwright() as playwright:
            options = {"headless": True}
            if os.environ.get("CHROMIUM_PATH"):
                options["executable_path"] = os.environ["CHROMIUM_PATH"]
            browser = playwright.chromium.launch(**options)
            page = browser.new_page(
                viewport={"width": 780, "height": 1000}, color_scheme="dark"
            )
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            # Icons are optional; checks must also work without a CDN connection.
            page.route("https://cdn.jsdelivr.net/**", lambda route: route.abort())
            page.goto(f"{origin}/previews/loot.html")
            assert page.locator(".cl-item").count() == 3
            first = page.locator('[data-item="0"]')
            assert first.locator(".cl-bar").get_attribute("aria-valuenow") == "3"
            assert first.locator("tbody tr").evaluate_all(
                "rows => rows.map(row => row.dataset.group)"
            ) == ["Need", "Greed", "Pass", "Waiting", "Waiting"]
            first.locator("[data-choice=Need]").click()
            assert first.locator(".cl-bar").get_attribute("aria-valuenow") == "4"
            page.locator("[data-action=advance]").click()
            assert first.locator(".cl-bar").get_attribute("data-complete") == "true"
            assert "awaiting server" in first.locator(".cl-result").inner_text()
            page.locator("[data-action=advance]").click()
            assert "You lost" in first.locator(".cl-result").inner_text()
            page.locator("[data-action=settings]").click()
            page.locator("[data-setting=layout]").select_option("tabs")
            assert page.locator(".cl-item").count() == 1
            page.locator('[data-tab="2"]').click()
            assert page.locator(".cl-name").inner_text() == "Tarratus Keystone"
            page.locator("[data-setting=layout]").select_option("windows")
            assert page.locator(".cl-item").count() == 3
            for width in (320, 520, 736):
                page.set_viewport_size({"width": width, "height": 1000})
                assert page.evaluate(
                    "document.documentElement.scrollWidth <= innerWidth"
                ), width

            page.goto(f"{origin}/previews/history.html")
            thorn = page.locator('[data-person="demo:thorn"]').locator("..").locator("..")
            assert "7 / 10" in thorn.inner_text()
            page.locator("[data-group]").select_option("aliases")
            page.locator('[data-person="alias:thorn / alts"]').click()
            assert "Contested wins in this tier: 9" in page.locator(
                ".lh-detail-meta"
            ).inner_text()
            assert page.locator(".lh-audit tbody tr").count() == 6
            for choice in ("Need", "Greed", "All"):
                page.locator("[data-choice]").select_option(choice)
                assert page.locator(".lh-stats tbody tr").count() > 0
            for width in (320, 520, 736):
                page.set_viewport_size({"width": width, "height": 1000})
                assert page.evaluate(
                    "document.documentElement.scrollWidth <= innerWidth"
                ), width
            assert not errors, errors
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
    print("PASS standalone previews: choices, progress, results, layouts, aliases, tiers, audit, responsive widths")


if __name__ == "__main__":
    main()
