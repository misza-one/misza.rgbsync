import QtQuick
import qs.Ui
import qs.Commons

// Label + value readout over a Ui/PanelSlider.
Column {
  id: root

  property QtObject bar: null
  property string label: ""
  property string valueText: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 100
  property real step: 1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal moved(real value)
  signal released(real value)

  spacing: Style.spacing.xs

  Item {
    width: parent.width
    height: Math.max(labelText.height, valueLabel.height)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: valueLabel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.valueText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSlider {
    width: parent.width
    bar: root.bar
    value: root.value
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    onMoved: function(value) { root.moved(value) }
    onReleased: function(value) { root.released(value) }
  }
}
