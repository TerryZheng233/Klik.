from pathlib import Path

app = Path(defines["app"]).resolve()

format = "UDZO"
files = [str(app)]
symlinks = {"Applications": "/Applications"}
icon = str(app / "Contents" / "Resources" / "Klik.icns")
background = str(Path(defines["background"]).resolve())
icon_locations = {"Klik.app": (182, 207), "Applications": (498, 207)}
window_rect = ((240, 160), (680, 400))
default_view = "icon-view"
icon_size = 90
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
