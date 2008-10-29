-- MySQL dump 10.11
--
-- Host: localhost    Database: www_wieismijnarts_nl
-- ------------------------------------------------------
-- Server version	5.0.67

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `Registration`
--

DROP TABLE IF EXISTS `Registration`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `Registration` (
  `registrationId` char(22) NOT NULL,
  `title` varchar(255) default NULL,
  `url` varchar(255) default NULL,
  `stepTemplateId` char(22) default NULL,
  `styleTemplateId` char(22) default NULL,
  `confirmationTemplateId` char(22) default NULL,
  `registrationCompleteTemplateId` char(22) default NULL,
  `noValidUserTemplateId` char(22) default NULL,
  `setupCompleteMailTemplateId` char(22) default NULL,
  `setupCompleteMailSubject` varchar(255) default NULL,
  `siteApprovalMailTemplateId` char(22) default NULL,
  `siteApprovalMailSubject` varchar(255) default NULL,
  `removeAccountWorkflowId` char(22) default NULL,
  `newAccountWorkflowId` char(22) default NULL,
  `registrationManagersGroupId` char(22) default NULL,
  `countLoginAsStep` tinyint(1) default '1',
  `countConfirmationAsStep` tinyint(1) default '1',
  `confirmationTitle` varchar(64) default NULL,
  `loginTitle` varchar(64) default NULL,
  PRIMARY KEY  (`registrationId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `RegistrationStep`
--

DROP TABLE IF EXISTS `RegistrationStep`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `RegistrationStep` (
  `stepId` char(22) NOT NULL,
  `registrationId` char(22) NOT NULL,
  `stepOrder` int(3) default NULL,
  `options` text,
  `namespace` varchar(255) default NULL,
  PRIMARY KEY  (`stepId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `Registration_status`
--

DROP TABLE IF EXISTS `Registration_status`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `Registration_status` (
  `registrationId` char(22) NOT NULL,
  `userId` char(22) NOT NULL,
  `status` char(20) NOT NULL default 'setup',
  `lastUpdate` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`registrationId`,`userId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `RegistrationStep_accountData`
--

DROP TABLE IF EXISTS `RegistrationStep_accountData`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `RegistrationStep_accountData` (
  `stepId` char(22) NOT NULL,
  `userId` char(22) NOT NULL,
  `status` char(20) default NULL,
  `configurationData` text,
  PRIMARY KEY  (`stepId`,`userId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
SET character_set_client = @saved_cs_client;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2008-10-29 12:06:41
