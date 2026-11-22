const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const workflow=fs.readFileSync('.github/workflows/deploy-error-report-functions-manual.yml','utf8');
test('report Edge Functions deployment is manual and requires exact production confirmation',()=>{
 assert.match(workflow,/workflow_dispatch/);
 assert.match(workflow,/DEPLOY ATINA REPORT FUNCTIONS/);
 assert.match(workflow,/if: inputs\.confirmation == 'DEPLOY ATINA REPORT FUNCTIONS'/);
 assert.doesNotMatch(workflow,/push:|pull_request:/);
});
test('deployment only targets report functions and fixed ATINA production ref',()=>{
 for(const fn of ['atina-error-reports-submit','atina-error-reports-admin'])assert.match(workflow,new RegExp('supabase functions deploy '+fn+' --project-ref qvvlqrgbtjujsejvenld'));
 assert.match(workflow,/supabase functions list --project-ref qvvlqrgbtjujsejvenld/);
 assert.match(workflow,/grep -F 'atina-error-reports-submit'/);
 assert.match(workflow,/grep -F 'atina-error-reports-admin'/);
 assert.doesNotMatch(workflow,/supabase db push|migration|render\.com|render-cli/i);
});
test('deployment uses token secret without printing it',()=>{
 assert.match(workflow,/secrets\.SUPABASE_ACCESS_TOKEN/);
 assert.doesNotMatch(workflow,/echo .*SUPABASE_ACCESS_TOKEN|printenv.*SUPABASE_ACCESS_TOKEN/i);
});
