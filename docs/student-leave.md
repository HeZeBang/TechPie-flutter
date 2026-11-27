# Student leave

The desktop `qjsqbd_qjxx` form has 22 field definitions. It uses two different attachment controls. The proof document (`ZMCL`, `uploadfile`) uses multipart field `bhFile`. The instructor acknowledgment (`YL7`, `cache-upload`) uses `files[]` by default. Its save step is asynchronous. A native client should await attachment persistence before submitting the application. The mobile form uses the image workflow described below.

The desktop application checks date overlap, commits the attachments and posts the form as `INDATA=JSON.stringify(form)` to `modules/leaveApply/addLeaveApply.do` or `editLeaveApply.do`. Success is `returnCode == "#E000000000000"`. A successful save triggers a separate school notification.

The history table applies the first matching condition.

| School state | Actions offered |
| --- | --- |
| `THZT == 1` | View and edit |
| Otherwise `SHZT == 0` | Edit and delete |
| `0 < SHZT < 99` | View, with withdrawal available only when `getNextState.do` for this leave type and duration returns the same approval state |
| `SHZT == 99` | View and print |

Withdrawal and deletion use `backleaveApply.do` and `delleaveApply.do` in the same module. The desktop helper posts a `requestParamStr` field containing a JSON object with the selected desktop record's `SQBH`. Both handlers check the same success code as the application. The mobile detail view uses a separate `leaveId`.

### Verified desktop submission and mobile readback

A student submitted one application with an ordinary proof image and no course attachment. The school displayed “保存成功！”. After refreshing the mobile page, the student history and detail views independently showed the new record and its pending review state.

| Stage | Observed calls | Result |
| --- | --- | --- |
| Open the form | `getAppliedDays.do`, `getNoRemoveLeave.do`, `getStuxslbdm.do`, `qjsqbd_jbxx.do`, `getLeaveType.do` and `getStuKcmc.do` | The form loaded the applicant context, leave types and course information. |
| Upload ordinary proof | `uploadTempFile.do` with multipart field `bhFile`, then `tempFileCheck.do` with `scope`, `fileToken` and `fileId` | Upload returned `success: true` and an ID. The check returned `check: true`. |
| Check eligibility and dates | `getAppliedDays.do`, `getNoRemoveLeave.do`, `getCaseByType.do` and `checkLeaveDate.do` | The last two POSTs wrapped `{QJLX, QJTS}` and `{XSBH, QJRQ}`, respectively, in `requestParamStr`. Each returned `#E000000000000`. |
| Persist and verify proof | `saveAttachment/{scope}/{token}.do` with `attachmentParam` containing `storeId`, `scope`, `fileToken` and `orderMap`, then `getUploadedAttachment/{token}.do` | The first POST returned `successCount: 1`. The second returned one item. |
| Create the application | `addLeaveApply.do` with `INDATA` | The response contained `returnCode` and `description`. The return code was `#E000000000000`. |
| Finish the form | A second `saveAttachment`, then `SentMassage.do` with `{QJLX, QJTS}` in `requestParamStr` | The second attachment call persisted zero items. The notification call returned `#E000000000000`. |
| Verify the application | Mobile `getStudentLeaveRecords.do`, then `getStudentLeaveRecordDetails.do` using the returned `leaveId` | The list was in `datas[0]`. The detail contained `leaveInfo` and `auditInfo`. Read the current status from `leaveInfo.auditStateDisplay`. The already-open mobile tab showed its old list until reloaded. |

The observed `INDATA` keys were `QJXZ_DISPLAY`, `QJXZ`, `QJLX_DISPLAY`, `QJLX`, `SQSM`, `QJKSRQ`, `QJJSRQ`, `QJTS`, `DZ_QJQX_DISPLAY`, `DZ_QJQX`, `DZ_XXDZ`, `DZ_KCMC`, `YL1` through `YL7`, `YL6_DISPLAY`, `QJSY`, `ZMCL`, `SQBH`, `XSBH`, `KSH` and `QJRQ`. This is the field set emitted by the school form. Server-required fields may be a subset.

The same record was withdrawn into draft, edited and resubmitted. Its details showed the changed reason and its status returned to pending review. A second withdrawal made it a draft again. Deletion followed by a fresh history query returned zero rows.

The school calendar initially submitted an empty `QJRQ` and an incorrect `QJTS` for the original one-day request. Its date check and edit call both failed. Selecting the original date explicitly produced a one-day request and a successful edit. TechPie derives both fields from the selected dates and stops when the school rejects a preflight check.

For approved records (`SHZT == 99`), the school opens the FineReport viewer with template `xsqj/SHKJ_XSQJD.cpt`. TechPie opens that report with the current school session after rechecking the record. The pending and draft states never offered print.

### Mobile proof and application

The mobile page loads `ydxsqjxs/dist/build.js`. The mobile student bundle references `getDefaultRole.do`, `getStuInfo.do`, `getDwInfo.do`, `getStudentAppliedDays.do`, `getDictionaryOfLeaveProperty.do`, `checkWhetherStudentCanApply.do`, `saveStudentLeaveRecord.do`, `getStudentLeaveRecords.do` and `getStudentLeaveRecordDetails.do` under `ekdz/MobileServiceStudentApply`. It also references `getLeaveType.do` and `getStuKcmc.do` under `modules/leaveApply`. Both proof fields use `emapm-upload-imgs`. Each accepts up to three camera or gallery images, each strictly smaller than 1,024,000 bytes. The ordinary proof picker updates `token`. The course acknowledgment picker updates `involveCourseToken`. The school requires ordinary proof when the proof field is shown. For a non-graduate applicant who selects instructor consent, it also requires the course acknowledgment. Selecting “涉及课程，未获得任课老师知情同意” blocks submission.

On the school mobile SDK path, `uploadImgsToEmap` calls `uploadTempFileAsAttachment.do` with the scope, file token and image store. The bridge checks every returned item's HTTP code and JSON `success` flag. The picker reads `getUploadedAttachment/{token}.do` to populate the previews and clears the token when no items come back. TechPie's existing WebView bridge targets the same upload endpoint. It builds a multipart request with `files[]`. [TechPie WebView bridge](../lib/services/webview_bridge.dart)

The page checks `datas[0].applicable` immediately before saving. It then issues a **state-changing GET** to `ekdz/MobileServiceStudentApply/saveStudentLeaveRecord.do`. The query uses the spelling `leavePorpertyId`. Both `proveFileToken` and `ZMCL` receive the ordinary proof token. `YL6` records course involvement and `YL7` carries the course acknowledgment token. The resolved save callback displays success and switches to history without inspecting a business receipt. If delivery is uncertain, check the student's existing leave records before allowing another submission. Keep this operation outside automatic GET retries.
