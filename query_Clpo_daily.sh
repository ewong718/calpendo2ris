##THIS SCRIPT RUNS DAILY at 12:10 am TO SEND ALL BOOKINGS OF CURRENT DAY
##Written by Edmund W. Wong
##Last Edited 6/13/2014


CONFIG_FILE="/home/csv-transfer/scripts/config.cfg"

if [[ -e "$CONFIG_FILE" ]]; then
	source "$CONFIG_FILE"
else echo "Operation aborted: config.cfg not found"; exit; fi

currentTime=`date +%Y%m%d%H%M%S`
currentDate=`date +%Y-%m-%d`

core () {

#This is where system user mysql writes the csv file to (only because mysql
#does not have the permission to write anywhere else)
TEMPDESTNAME="${TEMPDESTNAMEROOT}/CalpendoDaily${2}_${currentTime}.csv"

#This is where the file is moved to for AIG team to grab the csv file
DESTNAME="${DESTNAMEROOT}/CalpendoDaily${2}_${currentTime}.csv"

mysql -u "$CALPENDOUSER" -p"$CALPENDOPW" -h localhost -e "
use calpendo;

SELECT *
FROM((SELECT \"start_date\",\"finish_date\",\"mrn\",\"last_name\",\"first_name\",\"date_of_birth\",\"sex\",\"gco\",\"ordering_physician\",\"referring_physician\",\"exam_type\",\"resource\")
UNION ALL

(
select * from

(
    select

    date_format(calpendo.bookings.start_date,'%Y%m%d%H%i%s') as start_date,     #Start Date
    date_format(calpendo.bookings.finish_date,'%Y%m%d%H%i%s') as finish_date,   #Finish Date
    lpad(calpendo.bookings.mrn, 7, '0') as mrn,                                 #MRN
    calpendo.bookings.last_name,                                                #Last Name
    calpendo.bookings.first_name,                                               #First Name
    date_format(calpendo.bookings.date_of_birth,'%Y%m%d') as date_of_birth,     #DOB
    case calpendo.bookings.sex when 'Male' then 'M' when 'Female' then 'F' end as sex,  #Sex
    concat('GC',calpendo.projects.project_code) as gco, #GCO
    case
    when (calpendo.projects.PhysicianCactusID >= 100000) then concat(calpendo.projects.PhysicianCactusID,',',calpendo.projects.referring_physician)
    else
    concat(lpad(calpendo.projects.PhysicianCactusID, 5, '0'),',',calpendo.projects.referring_physician)
    end as ordering_physician,  #Ordering Physician
    case
    when (calpendo.projects.PhysicianCactusID >= 100000) then concat(calpendo.projects.PhysicianCactusID,',',calpendo.projects.referring_physician)
    else
    concat(lpad(calpendo.projects.PhysicianCactusID, 5, '0'),',',calpendo.projects.referring_physician)
    end as referring_physician, #Referring Physician
    calpendo.string_enum_values.ris_examcode as exam_type,                                                                      #RE ORG Exam Code

    case #Resource
    when (calpendo.bookings.blind_read = 'Blinded' AND calpendo.projects.specified_radiologist <> '')
    then concat('BLINDED READ, READER: ', calpendo.projects.specified_radiologist,', ',calpendo.resources.name)
    when (calpendo.bookings.blind_read = 'Blinded')
    then concat('BLINDED READ, ', calpendo.resources.name)
    when (calpendo.projects.specified_radiologist <> '')
    then concat('READER: ', calpendo.projects.specified_radiologist,', ',calpendo.resources.name)
    else
    calpendo.resources.name
    end as resource

    from calpendo.bookings
        inner join calpendo.projects
        on calpendo.bookings.project_id = calpendo.projects.id
        inner join calpendo.resources
        on calpendo.bookings.resource_id = calpendo.resources.id
        left join calpendo.string_enum_values
        on calpendo.bookings.$1 = calpendo.string_enum_values.value
        left join calpendo.resource_group_resources
        on calpendo.resources.id = calpendo.resource_group_resources.resource_id

    where

    (calpendo.bookings.development<>'Yes (Phantom)' AND calpendo.bookings.development<>'Yes (Animal)' AND calpendo.bookings.development<>'Standard of Care (SOC)' AND calpendo.bookings.development<>'SOC - Research') and
    calpendo.resource_group_resources.resource_group_id=2 and
    (calpendo.bookings.status = 'APPROVED' OR calpendo.bookings.status = 'REQUESTED') and
    (calpendo.projects.type_id=9 OR calpendo.projects.type_id=10 OR calpendo.projects.type_id=11) and #type_id 1 is human
    (calpendo.bookings.$1 IS NOT NULL AND calpendo.bookings.$1 != 'None Selected') and
    calpendo.bookings.start_date like '${currentDate}%' and
    calpendo.bookings.$1 not like 'PET%'
    order by start_date

) as table_before_examtype_null_filtered

where table_before_examtype_null_filtered.exam_type is not null

))

AS A
INTO OUTFILE '$TEMPDESTNAME'
FIELDS TERMINATED BY ','
ENCLOSED BY '\"'
LINES TERMINATED BY '\n';
"

no_rows=`cat $TEMPDESTNAME | wc | awk -F" " '{print $1}'`
if [ $no_rows -gt 1 ]
then
    cp -p $TEMPDESTNAME $DESTNAME
fi

}

core ExamType1
core ExamType2 ext2
core ExamType3 ext3
