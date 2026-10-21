#!/usr/bin/env python3
"""Prove reference-role metadata depends on UI ext_hlstate, in one owned child.

Run with the existing Notebook venv (pynvim). No user session/theme/build used.
"""
import json
from pathlib import Path
import re

import pynvim

bridge = (Path(__file__).resolve().parents[2] / "src/bridge/mod.rs").read_text()
assert bridge.count("options.set_hlstate_external(true);") == 1
# Inspect the attach block, ignoring comments, so a platform cfg cannot silently
# disable semantic highlight identities again (the Windows outline regression).
attach_block = bridge.split("let mut options = UiAttachOptions::new();", 1)[1]
attach_block = attach_block.split("options.set_hlstate_external(true);", 1)[0]
attach_block = re.sub(r"//[^\n]*", "", attach_block).rstrip()
assert not re.search(r"#\s*\[\s*cfg(?:_attr)?\b[^\n]*\]\s*$", attach_block), \
    "ext_hlstate must be requested at attach on every platform"

nvim = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n"])

def highlights():
    nvim.eval("1")
    result = []
    for kind, name, args in nvim._session._pending_messages:
        if kind == "notification" and name == "redraw":
            for event in args:
                if event[0] == "hl_attr_define":
                    result.extend(event[1:])
    nvim._session._pending_messages.clear()
    return result

try:
    nvim.ui_attach(60, 10, rgb=True, ext_linegrid=True, ext_hlstate=False)
    nvim.exec_lua("""
      vim.api.nvim_buf_set_lines(0,0,-1,false,{"local sample = sample + 1"})
      vim.api.nvim_set_hl(0,'LspReferenceText',{bg=0xcdd9cd,sp=0x399ee6})
      vim.api.nvim_buf_set_extmark(0,vim.api.nvim_create_namespace('owned references'),0,6,
        {end_col=12,hl_group='LspReferenceText'})
      vim.cmd.redraw()
    """)
    disabled = highlights()
    assert disabled and all(not packet[3] for packet in disabled), "disabled UI unexpectedly received group names"
    # The corrected frontend requests hlstate at attach, where Nvim initializes
    # semantic highlight identities. Reattach only this test's own fake UI.
    nvim.ui_detach()
    nvim.ui_attach(60, 10, rgb=True, ext_linegrid=True, ext_hlstate=True)
    nvim.command("redraw!")
    enabled = highlights()
    matching = [packet for packet in enabled if any(info.get("hi_name") == "LspReferenceText" for info in packet[3])]
    assert matching, "enabling UI metadata did not deliver LspReferenceText identity"
    assert any(packet[1].get("special") == 0x399ee6 for packet in matching), "special outline color was changed"
    assert nvim.api.list_uis()[0]["ext_hlstate"] is True
    assert nvim.current.buffer[:] == ["local sample = sample + 1"]
    print("PASS reference outline prerequisite: attach ext_hlstate=false sends zero group identities; attach true emits LspReferenceText with unchanged special RGB; renderer role can then match: " + json.dumps({"without_names": len(disabled), "reference_packets": len(matching)}))
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
    nvim.close()
