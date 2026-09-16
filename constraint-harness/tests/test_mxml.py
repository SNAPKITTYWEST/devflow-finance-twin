# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

"""MXML parse and validation tests."""

import pytest
from mxml.parser import parse_mxml, MXMLParseError
from mxml.validator import validate_mxml, ValidationError  # noqa: F401


VALID = """<?xml version="1.0"?>
<mxml version="1.0">
  <runtime id="t">
    <limits>
      <max_workers>2</max_workers>
      <max_revisions>1</max_revisions>
      <timeout_seconds>10</timeout_seconds>
    </limits>
    <constitution><axiom ref="schema"/></constitution>
    <commands><command id="py" type="python"/></commands>
    <tasks><task id="a" command="py"/></tasks>
  </runtime>
</mxml>
"""


def test_parse_valid():
    doc = parse_mxml(VALID)
    assert doc.version == "1.0"
    assert doc.runtime.id == "t"
    assert doc.runtime.limits.max_workers == 2
    assert len(doc.runtime.commands) == 1
    assert len(doc.runtime.tasks) == 1


def test_reject_missing_limits():
    bad = """<mxml version="1.0"><runtime id="x"><commands><command id="c" type="python"/></commands></runtime></mxml>"""
    with pytest.raises(MXMLParseError):
        parse_mxml(bad)


def test_reject_unknown_command_ref():
    bad = VALID.replace('command="py"', 'command="nope"')
    doc = parse_mxml(bad)
    with pytest.raises(ValidationError):
        validate_mxml(doc)


def test_reject_cycle():
    cyclic = """<?xml version="1.0"?>
<mxml version="1.0">
  <runtime id="c">
    <limits><max_workers>1</max_workers><max_revisions>0</max_revisions><timeout_seconds>5</timeout_seconds></limits>
    <commands><command id="py" type="python"/></commands>
    <tasks>
      <task id="a" command="py" depends_on="b"/>
      <task id="b" command="py" depends_on="a"/>
    </tasks>
  </runtime>
</mxml>
"""
    doc = parse_mxml(cyclic)
    with pytest.raises(ValidationError):
        validate_mxml(doc)


def test_self_dependency():
    src = """<?xml version="1.0"?>
<mxml version="1.0">
  <runtime id="s">
    <limits><max_workers>1</max_workers><max_revisions>0</max_revisions><timeout_seconds>5</timeout_seconds></limits>
    <commands><command id="py" type="python"/></commands>
    <tasks><task id="a" command="py" depends_on="a"/></tasks>
  </runtime>
</mxml>
"""
    doc = parse_mxml(src)
    with pytest.raises(ValidationError):
        validate_mxml(doc)
