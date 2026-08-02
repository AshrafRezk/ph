/* global Visualforce, CrmHubListController, crmHubOpenRecordModal */
(function (global) {
    'use strict';

    var hubNotifications = [];
    var hubNotificationsPollTimer = null;

    function hubNotifEsc(s) {
        if (s == null) {
            return '';
        }
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function hubNotifFormatTime(dateStr) {
        if (!dateStr) {
            return '';
        }
        var date = new Date(dateStr);
        var now = new Date();
        var diffMin = Math.floor((now - date) / 60000);
        if (diffMin < 1) {
            return 'just now';
        }
        if (diffMin < 60) {
            return diffMin + 'm ago';
        }
        var diffHr = Math.floor(diffMin / 60);
        if (diffHr < 24) {
            return diffHr + 'h ago';
        }
        var diffDay = Math.floor(diffHr / 24);
        if (diffDay < 7) {
            return diffDay + 'd ago';
        }
        return date.toLocaleDateString();
    }

    function hubNotifUpdateBadge(unreadCount) {
        var badge = document.getElementById('hubNotificationsBadge');
        if (!badge) {
            return;
        }
        if (unreadCount > 0) {
            badge.textContent = unreadCount > 99 ? '99+' : String(unreadCount);
            badge.style.display = 'block';
        } else {
            badge.style.display = 'none';
        }
    }

    function hubNotifRenderList(notifications) {
        var listEl = document.getElementById('hubNotificationsList');
        if (!listEl) {
            return;
        }

        if (!notifications || !notifications.length) {
            listEl.innerHTML = '<div class="hub-notif-empty">No notifications yet</div>';
            return;
        }

        listEl.innerHTML = notifications
            .map(function (notification) {
                var photoUrl = notification.actorPhotoUrl || '/img/icon/profile32.png';
                var unreadClass = notification.isRead ? '' : ' unread';
                var typeLabel = notification.type || 'Update';
                var title = hubNotifEsc(notification.title || typeLabel);
                var body = hubNotifEsc(notification.message || '');
                return (
                    '<button type="button" class="hub-notif-item' +
                    unreadClass +
                    '" data-notification-id="' +
                    hubNotifEsc(notification.id) +
                    '">' +
                    '<span class="hub-notif-avatar-wrap"><img src="' +
                    hubNotifEsc(photoUrl) +
                    '" alt="" class="hub-notif-avatar" /></span>' +
                    '<div class="hub-notif-content">' +
                    '<div class="hub-notif-title">' +
                    title +
                    '</div>' +
                    (body ? '<div class="hub-notif-body">' + body + '</div>' : '') +
                    '<div class="hub-notif-meta">' +
                    '<span class="hub-notif-pill">' +
                    hubNotifEsc(typeLabel) +
                    '</span>' +
                    '<span>' +
                    hubNotifFormatTime(notification.createdDate) +
                    '</span>' +
                    '</div></div></button>'
                );
            })
            .join('');

        listEl.querySelectorAll('.hub-notif-item').forEach(function (itemEl) {
            itemEl.addEventListener('click', function () {
                var notificationId = itemEl.getAttribute('data-notification-id');
                var notification = hubNotifications.find(function (row) {
                    return row.id === notificationId;
                });
                if (notification) {
                    hubNotifOpen(notification);
                }
            });
        });
    }

    function hubNotifLoad() {
        if (typeof CrmHubListController === 'undefined' || typeof CrmHubListController.fetchNotifications !== 'function') {
            return;
        }
        Visualforce.remoting.timeout = 120000;
        CrmHubListController.fetchNotifications(25, function (result, event) {
            if (!event.status || !result) {
                return;
            }
            hubNotifications = result.notifications || [];
            hubNotifUpdateBadge(result.unreadCount || 0);
            var dropdown = document.getElementById('hubNotificationsDropdown');
            if (dropdown && dropdown.classList.contains('show')) {
                hubNotifRenderList(hubNotifications);
            }
        });
    }

    function hubNotifToggle(event) {
        if (event) {
            event.stopPropagation();
        }
        var dropdown = document.getElementById('hubNotificationsDropdown');
        if (!dropdown) {
            return;
        }
        var willShow = !dropdown.classList.contains('show');
        dropdown.classList.toggle('show', willShow);
        if (willShow) {
            hubNotifRenderList(hubNotifications);
            hubNotifLoad();
        }
    }

    function hubNotifClose() {
        var dropdown = document.getElementById('hubNotificationsDropdown');
        if (dropdown) {
            dropdown.classList.remove('show');
        }
    }

    function hubNotifMarkRead(notificationIds, markAll, callback) {
        if (typeof CrmHubListController === 'undefined' || typeof CrmHubListController.markNotificationsRead !== 'function') {
            if (typeof callback === 'function') {
                callback(false, 0);
            }
            return;
        }
        Visualforce.remoting.timeout = 120000;
        CrmHubListController.markNotificationsRead(
            JSON.stringify(notificationIds || []),
            markAll === true,
            function (result, event) {
                if (event.status) {
                    hubNotifLoad();
                }
                if (typeof callback === 'function') {
                    callback(event.status, result);
                }
            }
        );
    }

    function hubNotifOpen(notification) {
        if (!notification) {
            return;
        }
        hubNotifClose();
        hubNotifMarkRead([notification.id], false);

        if (notification.recordId && typeof global.crmHubOpenRecordModal === 'function') {
            global.crmHubOpenRecordModal(notification.recordId);
        }
    }

    function hubNotifMarkAllRead() {
        hubNotifMarkRead([], true);
    }

    function hubNotifInit() {
        hubNotifLoad();
        if (hubNotificationsPollTimer) {
            clearInterval(hubNotificationsPollTimer);
        }
        hubNotificationsPollTimer = setInterval(hubNotifLoad, 60000);

        document.addEventListener('click', function (event) {
            var container = document.querySelector('.hub-notif-bell');
            if (container && !container.contains(event.target)) {
                hubNotifClose();
            }
        });
    }

    global.hubNotifToggle = hubNotifToggle;
    global.hubNotifMarkAllRead = hubNotifMarkAllRead;
    global.hubNotifInit = hubNotifInit;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', hubNotifInit);
    } else {
        hubNotifInit();
    }
})(typeof window !== 'undefined' ? window : this);
