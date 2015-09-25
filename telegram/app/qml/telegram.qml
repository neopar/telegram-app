/*
 * Copyright 2015 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.4
//import QtMultimedia 5.0

import Ubuntu.Components 1.2
import Ubuntu.Components.Popups 0.1 as Popup
import Ubuntu.Content 0.1
//import UserMetrics 0.1
import Ubuntu.OnlineAccounts.Client 0.1
import Ubuntu.PushNotifications 0.1

import TelegramQML 1.0

import "components"
import "js/version.js" as Version
import "ui"

MainView {
    id: mainView
    width: units.gu(38)
    height: units.gu(50)
    focus: true

    applicationName: "com.ubuntu.telegram"
    anchorToKeyboard: true
    automaticOrientation: false

    property string appId: "com.ubuntu.telegram_telegram" // no-i18n

    property variant panel


    property alias profiles: profile_model
    property alias pushClient: push_client_loader.item
    property string currentPageName: pageStack.currentPage ? pageStack.currentPage.objectName : ""
    property string pushProfile: "" // selected profile == first profile
    property bool readyForPush: false // first Tg client connected

    property var uri: undefined
    property int chatToOpen: 0

    signal error(int id, string errorCode, string errorText)
    signal pushLoaded()
    signal pushRegister(string token, string version)
    signal pushUnregister(string token)

    function showIntro() {
        if (profiles.count == 0) {
            pageStack.clear();
            pageStack.push(intro_page_component);
        }
    }
    
    onActiveFocusChanged: {
        if (activeFocus) {
            processUri();
            if (!pushClient.registered && Cutegram.pushNotifications) {
                console.log("push - retrying registration");
                pushClient.appId = "push-bug-workaround";
                pushClient.appId = mainView.appId;
            } else if (currentPageName == "dialogPage") {
                var tag = pageStack.currentPage.dialogId;
                pushClient.clearPersistent([tag]);
            }
        }
    }

    Component.onCompleted: {
        showIntro();

        if (profiles.count > 0 && Cutegram.hasArgs() > 0) {
            console.log("push - started from notification");
            mainView.uri = Cutegram.args[0];
            processUri();
        }
    }

    function backToDialogsPage() {
        while (pageStack.depth > 0 &&
                pageStack.currentPage.objectName !== "accountPage") {
            pageStack.pop();
        }
    }

    function openPushDialog() {
        Cutegram.promptForPush = true;
        if (push_dialog_loader.status === Loader.Ready) {
            PopupUtils.open(push_dialog_component);
        } else {
            push_dialog_loader.active = true;
        }
    }

    function processUri() {
        if (typeof mainView.uri === "undefined") return;
        var commands = mainView.uri.split("://")[1].split("/");
        if (commands) {
            switch(commands[0].toLowerCase()) {
            case "chat": // no-i18n
                var chatId = parseInt(commands[1]);
                if (isNaN(chatId) || chatId === 0) {
                    console.info("Not setting chat to open.");
                    backToDialogsPage(); // TODO
                    // TODO: Temporarily open no chats if secret notification pressed.
                } else {
                    console.info("Setting chat to open: " + chatId);
                    backToDialogsPage();
                    mainView.chatToOpen = chatId;
                    mainView.uri = undefined;
                }
            case "launch": // no-i18n
                // Nothing to do.
                break;
            default: console.warn("Unmanaged URI! " + commands);
            }
        }
        commands = undefined;
    }

    Connections {
        target: UriHandler
        onOpened: {
            mainView.uri = uris[0];
            processUri();
        }
    }

    Connections {
        target: Cutegram
        onLoggedOut: {
            pageStack.clear();
            profiles.remove(phone);
        }
    }

    ProfilesModel {
        id: profile_model
        configPath: AsemanApp.homePath
    }

    AccountListFrame {
        id: account_list

        onUnreadCountChanged: {
            pushClient.count = unreadCount;
            if (unreadCount == 0) {
                pushClient.clearPersistent([]);
            }
        }
    }

    PageStack {
        id: pageStack

        Component {
            id: intro_page_component

            IntroPage {
                onStartMessaging: {
                    pageStack.push(auth_countries_page_component);
                }
            }
        }

        Component {
            id: auth_countries_page_component

            AuthCountriesPage {
                onCountryEntered: {
                    pageStack.push(auth_number_page_component, {
                            "countryCode": code
                    });
                }
            }
        }

        Component {
            id: auth_number_page_component

            AuthNumberPage {
                id: auth_number_page

                onPhoneEntered: {
                    var profile = profiles.add(number)
                    // umm... taken from Cutegram. Prolly just a generic placeholder.
                    profile.name = "AA";
                }

                Connections {
                    target: mainView
                    onError: auth_number_page.error(id, errorCode, errorText)
                }
            }
        }

        Component {
            id: preview_page_component
            PreviewPage {}
        }

        Component {
            id: picker_page_component
            PickerPage {}
        }

        Component {
            id: add_contact_page_component
            AddContactPage {}
        }
    }

    Component {
        id: panel_component
        AccountPanel {
            pageStack: mainView.pageStack

            onSettingsClicked: {
                // TODO settings
            }

            onFaqClicked: {
                Qt.openUrlExternally("https://telegram.org/faq");
            }

            onAddAccountClicked: {
                pageStack.push(auth_countries_page_component);
            }

            onAccountClicked: {
                account_list.accountList.accountSelected(number);
            }
        }
    }

    Setup {
        id: setup
        applicationId: "com.ubuntu.telegram_telegram" // no-i18n
        providerId: "ubuntuone" // no-i18n
    }

    Loader {
        id: push_client_loader
        active: false
        asynchronous: false
        sourceComponent: PushClient {
            id: push_client
            appId: mainView.appId

            property bool registered: false
            property bool loggedIn: readyForPush

            function registerForPush() {
                if (registered) return;

                if (!Cutegram.pushNotifications) {
                    console.warn("push - ignoring, notifications disabled");
                    return;
                }

                if (token.length === 0) {
                    console.warn("push - can't register, empty token.");
                    return;
                }
                if (!readyForPush) {
                    console.warn("push - can't register, not logged-in yet.");
                    return;
                }

                console.log("push - registering with Telegram");
                registered = true;
                pushRegister(token, Version.version);
            }

            function unregisterFromPush() {
                console.log("push - unregistering from Telegram");
                pushUnregister(token);
                registered = false;
            }

            onTokenChanged: {
                console.log("push - token changed: " + (token.length > 0 ? "present" : "empty!"));
                if (token.length > 0) {
                    registered = false;
                    registerForPush();
                }
            }

            // onConnectedChanged: {
            //     if (token.length > 0) {
            //         registerForPush();
            //     }
            // }

            onError: {
                if (status == "bad auth") {
                    console.warn("push - 'bad auth' error: " + status);
                    if (Cutegram.promptForPush) {
                        push_dialog_loader.active = true;
                    }
                } else {
                    console.warn("push - unhandled error: " + status);
                }
            }
        }

        onStatusChanged: {
            if (status === Loader.Loading) {
                console.log("push - push client loading");
            } else if (status === Loader.Ready) {
                console.log("push - push client loaded");
            }
        }

        onLoaded: {
            pushLoaded();
        //    pushClient.notificationsChanged.connect(telegramClient.onPushNotifications);
        //    pushClient.error.connect(telegramClient.onPushError);
        }
    }

    Loader {
        id: push_dialog_loader
        active: false
        asynchronous: false
        sourceComponent: Component {
            id: push_dialog_component
            Popup.Dialog {
                id: push_dialog
                title: i18n.tr("Notifications")
                text: i18n.tr("If you want Telegram notifications when you're not using the app, sign in to your Ubuntu One account.")

                function close() {
                    PopupUtils.close(push_dialog);
                }

                Button {
                    text: i18n.tr("Sign in to Ubuntu One")
                    color: UbuntuColors.orange
                    onClicked: {
                        setup.exec();
                        close();
                    }
                }
                Button {
                    text: i18n.tr("Remind me later")
                    onClicked: {
                        Cutegram.promptForPush = true;
                        Cutegram.pushNotifications = false;
                        close();
                    }
                }
                Button {
                    text: i18n.tr("Don't want notifications")
                    onClicked: {
                        Cutegram.promptForPush = false;
                        Cutegram.pushNotifications = false;
                        pushClient.unregisterFromPush();
                        close();
                    }
                }
            }
        }

        onLoaded: {
            openPushDialog();
        }
    }

    Item {
        id: encryptedTypes

        property real typeEncryptedChatEmpty: 0xab7ec0a0
        property real typeEncryptedChatWaiting: 0x3bf703dc
        property real typeEncryptedChatRequested: 0xc878527e
        property real typeEncryptedChat: 0xfa56ce36
        property real typeEncryptedChatDiscarded: 0x13d6dd27
    }

    Item {
        id: userStatusType

        property real typeUserStatusEmpty: 0x9d05049
        property real typeUserStatusOnline: 0xedb93949
        property real typeUserStatusOffline: 0x8c703f
        property real typeUserStatusRecently: 0xe26f42f1
        property real typeUserStatusLastWeek: 0x7bf09fc
        property real typeUserStatusLastMonth: 0x77ebc742
    }

    Item {
        id: userType

        property real typeUserEmpty: 0x200250ba
        property real typeUserDeleted: 0xd6016d7a
    }
}