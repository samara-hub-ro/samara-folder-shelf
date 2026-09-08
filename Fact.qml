import QtQuick
import qs.Commons

// One "label value" pair from the preview's facts grid. A file of its own
// because an inline component has to be declared against the document root,
// and this one belongs several objects deep.
Row {
  id: fact

  property string label: ""
  property string value: ""
  property color tone: Color.tooltip.text
  property bool dimmed: false

  spacing: Style.space(8)

  Text {
    text: fact.label
    color: Qt.rgba(fact.tone.r, fact.tone.g, fact.tone.b, 0.45)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    text: fact.value
    color: Qt.rgba(fact.tone.r, fact.tone.g, fact.tone.b, fact.dimmed ? 0.62 : 0.95)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: !fact.dimmed
  }
}
