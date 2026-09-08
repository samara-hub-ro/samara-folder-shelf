import QtQuick
import qs.Commons

// The shelf's surface, and the preview card's, and the menu's.
//
// "Glass" on a compositor that blurs for you is mostly restraint: the blur is
// Hyprland's layerrule, and everything here is the thin film on top of it —
// a wash of the theme colour at the opacity the user chose, a vertical
// gradient so the pane has a top and a bottom, a diagonal bloom of the accent
// from the upper left, and a specular line just under the top edge. Overdo
// any of them and the blur stops reading as depth and starts reading as fog.
//
// Every layer is a rounded rectangle in its own right rather than a shape cut
// out of a mask. The masked version of this worked on the shelf and drew
// nothing at all inside the picker, and a surface that renders or not
// depending on which window it lands in is not worth the corners it buys —
// especially when four plain rectangles cost nothing and cannot fail.
//
// The one thing here that is ours rather than Cupertino's is the spine: a
// hairline of the theme accent down the left edge, brightest at the top,
// which is what you recognise the shelf by from across a desktop.
Item {
  id: root

  property real radius: Style.space(18)
  property color tint: Color.popups.background
  property real backgroundOpacity: 0.8
  property color rim: Color.foreground
  property color accent: Color.accent
  property bool showSpine: true
  property bool elevated: false
  property real accentBloom: 0.10

  // The wash.
  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.backgroundOpacity)
  }

  // Lit from above. Without it the surface is a flat rectangle of colour no
  // matter how much the compositor blurs behind it.
  Rectangle {
    anchors.fill: parent
    radius: root.radius
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
      GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.015) }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
    }
  }

  // The accent bloom, on the diagonal. A radial gradient would be truer to
  // the idea of a light source and would need a mask to keep it inside the
  // corners; this reads the same and does not.
  Rectangle {
    anchors.fill: parent
    radius: root.radius
    opacity: root.accentBloom
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.9) }
      GradientStop { position: 0.5; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  // The rim.
  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, root.elevated ? 0.26 : 0.16)
  }

  // The specular line: a highlight inset just under the top edge, fading out
  // towards both corners so it never meets the rim and turns into a box.
  Rectangle {
    x: root.radius
    y: 1
    width: Math.max(0, parent.width - root.radius * 2)
    height: 1
    opacity: root.elevated ? 0.9 : 0.6
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.30) }
      GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.30) }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  // The spine.
  Rectangle {
    visible: root.showSpine
    x: 1
    y: root.radius * 0.6
    width: Math.max(1, Style.space(2))
    height: Math.max(0, parent.height - root.radius * 1.2)
    radius: width / 2
    opacity: root.elevated ? 0.9 : 0.65
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85) }
      GradientStop { position: 0.7; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) }
      GradientStop { position: 1.0; color: "transparent" }
    }
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }
}
