import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';
import { newClientKey } from 'c/clmOfflineStore';

async function saveAndSubmit(params = {}) {
    const input = params.input || params;
    if (!input?.accountId) {
        throw Object.assign(new Error('Choose a pharmacy (or hospital/chain) for this order.'), {
            body: { message: 'Choose a pharmacy (or hospital/chain) for this order.' }
        });
    }
    const lines = (input.lines || []).filter((line) => line?.productId && Number(line.quantity) >= 1);
    if (!lines.length) {
        throw Object.assign(new Error('Add at least one product with a quantity.'), {
            body: { message: 'Add at least one product with a quantity.' }
        });
    }

    const totalQuantity = lines.reduce((sum, line) => sum + Number(line.quantity || 0), 0);
    let orderType = input.orderType || 'Direct';
    if (totalQuantity > 200) {
        orderType = 'Distributor';
    }
    if (orderType === 'Distributor' && !String(input.distributorName || '').trim()) {
        throw Object.assign(new Error('Pick a distributor for distributor orders.'), {
            body: { message: 'Pick a distributor for distributor orders.' }
        });
    }

    const submitNow = input.submitNow === true;
    const skipFull = totalQuantity <= 10;
    let status = 'Draft';
    if (submitNow) {
        status = skipFull ? 'Pending Finance' : 'Pending DM';
    }

    const header = {
        Account__c: input.accountId,
        Visit__c: input.visitId || null,
        Order_Type__c: orderType,
        Distributor_Name__c: input.distributorName || null,
        Branch_Name__c: input.branchName || null,
        Discount_Percent__c: input.discountPercent != null ? Number(input.discountPercent) : null,
        FOC__c: input.foc === true,
        Notes__c: input.notes || null,
        Source__c: input.source || 'Home',
        Total_Quantity__c: totalQuantity,
        Skip_Full_Approval__c: skipFull,
        Status__c: status,
        Submitted_Date__c: submitNow ? new Date().toISOString() : null,
        lines
    };

    if (isOfflineMode()) {
        const clientKey = newClientKey('field-order');
        await queueOfflineAction({
            actionType: 'CREATE_FIELD_ORDER',
            clientActionKey: clientKey,
            payloadJson: JSON.stringify({ ...header, submitNow })
        });
        return {
            id: clientKey,
            name: 'Pending sync',
            accountId: input.accountId,
            visitId: input.visitId || null,
            orderType,
            status,
            statusLabel: status,
            totalQuantity,
            skipFullApproval: skipFull,
            offline: true
        };
    }

    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        if (identity?.user_id) {
            header.Requested_By__c = identity.user_id;
            if (submitNow && !skipFull) {
                const users = await plannerApiFetch(
                    `/services/data/v62.0/query?q=${encodeURIComponent(
                        `SELECT ManagerId FROM User WHERE Id = '${identity.user_id}' LIMIT 1`
                    )}`
                );
                const managerId = users?.records?.[0]?.ManagerId || null;
                if (managerId) {
                    header.Current_Approver__c = managerId;
                }
            }
        }
    } catch (_err) {
        // continue
    }

    const { lines: linePayload, submitNow: _s, ...orderPayload } = header;
    const created = await plannerApiFetch('/services/data/v62.0/sobjects/Field_Order__c', {
        method: 'POST',
        body: JSON.stringify(orderPayload)
    });

    let display = 1;
    for (const line of lines) {
        await plannerApiFetch('/services/data/v62.0/sobjects/Field_Order_Line__c', {
            method: 'POST',
            body: JSON.stringify({
                Field_Order__c: created.id,
                Product2__c: line.productId,
                Quantity__c: Number(line.quantity),
                Notes__c: line.notes || null,
                Display_Order__c: display
            })
        });
        display += 1;
    }

    return {
        id: created.id,
        name: created.id,
        accountId: input.accountId,
        visitId: input.visitId || null,
        orderType,
        status,
        statusLabel: status,
        totalQuantity,
        skipFullApproval: skipFull
    };
}

export default makeDualApex(saveAndSubmit);
