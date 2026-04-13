import QtQuick

Rectangle {
    id: root
    property string state: "saved"
    width: 12; height: 12; radius: 6
    color: state === "saved" ? "#4caf50"
         : state === "dirty" ? "#ff9800"
         : "#f44336"
}
