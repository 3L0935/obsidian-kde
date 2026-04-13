import QtQuick

Rectangle {
    id: root
    property string indicatorState: "saved"
    width: 12; height: 12; radius: 6
    color: indicatorState === "saved" ? "#4caf50"
         : indicatorState === "dirty" ? "#ff9800"
         : "#f44336"
}
