import QtQuick
import Qt.labs.folderlistmodel

FolderListModel {
    showDirs: true
    showFiles: true
    showHidden: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    nameFilters: ["*"]
}
